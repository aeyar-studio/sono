import Foundation
import Sparkle

/// Auto-updates for a directly distributed app.
///
/// Sparkle does the work: it fetches an appcast, verifies the download against the
/// EdDSA public key in Info.plist, swaps the bundle and relaunches. That signature
/// is the security model. Even someone who took over the domain could not push a
/// malicious update without the private key, which lives only in the Keychain.
///
/// The one network call is a small XML fetch. Nothing about the user's dictation
/// is involved, and system profiling is disabled in Info.plist so the check
/// carries no hardware or OS details.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    /// Set when a newer version exists, so the sidebar can offer it in place.
    /// Sparkle's own window then handles the install, which is worth keeping:
    /// its download, verify, swap and relaunch flow is long-proven, and a custom
    /// reimplementation is a bad thing to get subtly wrong.
    @Published private(set) var availableVersion: String?
    @Published var automaticChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticChecks }
    }

    private var controller: SPUStandardUpdaterController?

    private override init() {
        automaticChecks = Settings.automaticUpdateChecks
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: true,
                                                 updaterDelegate: self,
                                                 userDriverDelegate: nil)
        controller?.updater.automaticallyChecksForUpdates = automaticChecks
    }

    /// Shows Sparkle's update window. Also used by the sidebar banner.
    func checkForUpdates() {
        controller?.updater.checkForUpdates()
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var lastChecked: Date? {
        controller?.updater.lastUpdateCheckDate
    }
}

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        Task { @MainActor in self.availableVersion = item.displayVersionString }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        Task { @MainActor in self.availableVersion = nil }
    }

    /// A failed check must be silent. Being offline is not an error worth a dialog,
    /// and it must never interrupt dictation.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { }
}
