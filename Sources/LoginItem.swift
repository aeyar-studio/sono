import Foundation
import ServiceManagement

/// The "Open at login" switch, backed by the system rather than a preference.
///
/// `enabled` is read from `SMAppService`, never stored. If someone removes Sono
/// under System Settings → General → Login Items, the switch reflects that the
/// next time the app launches instead of insisting on a value we wrote down.
@MainActor
final class LoginItemStore: ObservableObject {
    static let shared = LoginItemStore()

    @Published private(set) var enabled: Bool

    /// Why the last change did not take, or nil when it did.
    ///
    /// Registration genuinely fails: most often because the app is being run
    /// from the disk image or the Downloads folder rather than Applications,
    /// and macOS will not add a login item for a bundle in a volatile location.
    /// Without this the switch simply flicked back to off and read as broken.
    @Published private(set) var problem: String?

    private init() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func syncFromSystem() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ newValue: Bool) {
        problem = nil
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            problem = explain(error)
        }
        // Always resync: the system is the truth, whether or not the call threw.
        syncFromSystem()
    }

    /// `SMAppService` errors surface as Cocoa codes with unhelpful text, so the
    /// common cause gets a sentence someone can act on.
    private func explain(_ error: Error) -> String {
        let ns = error as NSError
        if !Bundle.main.bundlePath.hasPrefix("/Applications") {
            return "Move Sono to your Applications folder first"
        }
        if ns.code == 1 {
            return "macOS blocked it. Allow Sono under Login Items in System Settings"
        }
        return ns.localizedDescription
    }
}
