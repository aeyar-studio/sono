import Foundation
import AppKit
import IOKit

/// Trial and licence state.
///
/// The trial is metered in **words dictated**, not days: a dictation tool gets
/// used in bursts, and a calendar trial expires while someone is busy and never
/// shows them the value. Words only tick up when Sono is actually earning its fee.
///
/// Verification talks to Dodo Payments' activate/validate endpoints, which are
/// public — no API key ships in the app. Deliberately not hardened beyond that:
/// anyone willing to patch the binary was never going to pay, and DRM would only
/// cost paying users reliability.
@MainActor
final class Licensing: ObservableObject {
    static let shared = Licensing()

    /// Free words before payment is required. Generous on purpose — roughly an
    /// hour of real dictation, enough to form a habit.
    static let trialWordLimit = 2_000

    /// Where "Buy" sends people. Swap for the Dodo Payments checkout link once
    /// the product is live; the site can redirect in the meantime.
    static let buyURL = "https://heysono.app/buy"

    enum State: Equatable {
        case trial(wordsUsed: Int)
        case licensed
        case trialEnded

        var isUnlocked: Bool { self != .trialEnded }
    }

    @Published private(set) var state: State = .trial(wordsUsed: 0)
    /// Set when an activation attempt fails, for display in Settings.
    @Published var lastError: String?
    @Published var isWorking = false

    private enum Key {
        static let words = "trialWords"
        static let license = "licenseKey"
        static let instance = "activationInstance"
        /// Hardware ID the stored activation belongs to.
        static let device = "activationDevice"
        static let validated = "lastValidated"
    }

    /// How long between server checks. A revoked or refunded key stops working
    /// within a week, without pestering the server on every launch.
    private static let revalidateAfter: TimeInterval = 7 * 24 * 60 * 60

    private init() {
        if Keychain.get(Key.license) != nil {
            state = .licensed
        } else {
            state = Self.stateForWords(wordsUsed)
        }
    }

    // MARK: - Trial metering

    var wordsUsed: Int { Int(Keychain.get(Key.words) ?? "") ?? 0 }

    var wordsRemaining: Int { max(0, Self.trialWordLimit - wordsUsed) }

    private static func stateForWords(_ used: Int) -> State {
        used >= trialWordLimit ? .trialEnded : .trial(wordsUsed: used)
    }

    /// Called after each dictation. No-op once licensed.
    func recordDictation(words: Int) {
        guard state != .licensed, words > 0 else { return }
        let total = wordsUsed + words
        Keychain.set(String(total), for: Key.words)
        state = Self.stateForWords(total)
    }

    // MARK: - Activation

    /// Dodo's activate/validate/deactivate endpoints are public, so this needs no
    /// secret. Switch to the test host while wiring up a store.
    private static let host = "https://live.dodopayments.com"

    func activate(key rawKey: String) async {
        let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        isWorking = true
        lastError = nil
        defer { isWorking = false }

        do {
            let body: [String: String] = ["license_key": key, "name": Self.deviceName]
            let json = try await post("/licenses/activate", body: body)
            guard let instance = json["id"] as? String else {
                lastError = "That key could not be activated. Check it and try again."
                return
            }
            Keychain.set(key, for: Key.license)
            Keychain.set(instance, for: Key.instance)
            Keychain.set(Self.hardwareID, for: Key.device)
            Keychain.set(String(Date().timeIntervalSince1970), for: Key.validated)
            state = .licensed
        } catch {
            lastError = "Couldn't reach the licence server. Check your connection."
        }
    }

    /// Called at launch. Checks with the server at most weekly, and only revokes
    /// when it explicitly says the key is invalid — a network failure must never
    /// lock someone out of their own app.
    func validateIfNeeded() async {
        guard let key = Keychain.get(Key.license) else { return }

        // The machine changed under a restored backup or a cloned disk: the stored
        // activation belongs to different hardware, so activate this Mac properly
        // rather than silently riding the old instance.
        if let boundTo = Keychain.get(Key.device), boundTo != Self.hardwareID {
            clearLocalLicense()
            await activate(key: key)
            return
        }

        let last = Double(Keychain.get(Key.validated) ?? "") ?? 0
        guard Date().timeIntervalSince1970 - last > Self.revalidateAfter else { return }

        do {
            let json = try await post("/licenses/validate", body: ["license_key": key])
            if let valid = json["valid"] as? Bool, valid == false {
                clearLocalLicense()
                state = Self.stateForWords(wordsUsed)
                lastError = "This licence is no longer valid."
            } else {
                Keychain.set(String(Date().timeIntervalSince1970), for: Key.validated)
            }
        } catch {
            // Offline, or their API is down: keep working, try again next launch.
        }
    }

    /// Frees this Mac's activation slot — for selling or handing on a machine.
    func deactivateThisMac() async {
        guard let key = Keychain.get(Key.license) else { return }
        isWorking = true
        defer { isWorking = false }
        if let instance = Keychain.get(Key.instance) {
            _ = try? await post("/licenses/deactivate",
                                body: ["license_key": key, "license_key_instance_id": instance])
        }
        clearLocalLicense()
        state = Self.stateForWords(wordsUsed)
    }

    private func clearLocalLicense() {
        Keychain.delete(Key.license)
        Keychain.delete(Key.instance)
        Keychain.delete(Key.device)
        Keychain.delete(Key.validated)
    }

    // MARK: - Plumbing

    /// Stable per-Mac identifier from the IOKit registry. Used so an activation
    /// is bound to hardware rather than to a name — two Macs both called
    /// "MacBook Air" were previously indistinguishable to the licence server, and
    /// reinstalling could silently burn a second activation slot.
    private static var hardwareID: String {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else { return "unknown" }
        defer { IOObjectRelease(service) }
        guard let property = IORegistryEntryCreateCFProperty(service, "IOPlatformUUID" as CFString,
                                                            kCFAllocatorDefault, 0),
              let uuid = property.takeRetainedValue() as? String else { return "unknown" }
        return uuid
    }

    /// Human-readable in Dodo's dashboard, unique per machine.
    private static var deviceName: String {
        let name = Host.current().localizedName ?? "Mac"
        return "\(name) · \(hardwareID.prefix(8))"
    }

    private func post(_ path: String, body: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: Self.host + path)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15

        let (data, _) = try await URLSession.shared.data(for: request)
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
