import Foundation
import AppKit
import IOKit

/// Trial and licence state.
///
/// The trial is metered in **dictations**, not days and not words. A dictation
/// tool gets used in bursts, so a calendar trial expires while someone is busy
/// and never shows them the value. Counting words looked fairer but distributed
/// the trial unevenly: short Slack replies bought fifty chances to be impressed,
/// while someone dictating emails burnt the allowance in eight. Counting uses
/// gives everyone the same number of moments, which is what actually convinces.
///
/// Verification talks to Dodo Payments' activate/validate endpoints, which are
/// public — no API key ships in the app. Deliberately not hardened beyond that:
/// anyone willing to patch the binary was never going to pay, and DRM would only
/// cost paying users reliability.
@MainActor
final class Licensing: ObservableObject {
    static let shared = Licensing()

    /// Free dictations before payment is required. Enough to form a habit and to
    /// hit the wall while enthusiasm is still high, which is when people buy.
    static let trialLimit = 30

    /// Where "Buy" sends people. Swap for the Dodo Payments checkout link once
    /// the product is live; the site can redirect in the meantime.
    static let buyURL = "https://heysono.app/buy"

    enum State: Equatable {
        case trial(used: Int)
        case licensed
        case trialEnded

        var isUnlocked: Bool { self != .trialEnded }
    }

    @Published private(set) var state: State = .trial(used: 0)
    /// Set when an activation attempt fails, for display in Settings.
    @Published var lastError: String?
    @Published var isWorking = false

    private enum Key {
        /// Historic name kept so existing installs do not get a fresh trial.
        static let used = "trialWords"
        static let license = "licenseKey"
        static let instance = "activationInstance"
        /// Hardware ID the stored activation belongs to.
        static let device = "activationDevice"
        static let validated = "lastValidated"
        /// When this install first ran. Kept separately from the word counter so
        /// that clearing the counter alone does not hand back a fresh trial on an
        /// install that has been around for months.
        static let firstRun = "firstRun"
    }

    /// A trial that has existed longer than this cannot be restarted by wiping the
    /// counter. Generous: someone who genuinely trialled Sono, left it for a month
    /// and came back still gets their remaining dictations.
    private static let trialWindow: TimeInterval = 45 * 24 * 60 * 60

    /// How long between server checks. A revoked or refunded key stops working
    /// within a week, without pestering the server on every launch.
    private static let revalidateAfter: TimeInterval = 7 * 24 * 60 * 60

    private init() {
        if Keychain.get(Key.firstRun) == nil {
            Keychain.set(String(Date().timeIntervalSince1970), for: Key.firstRun)
        }
        if Keychain.get(Key.license) != nil {
            state = .licensed
        } else {
            state = stateFor(used)
        }
    }

    /// Days since this install first ran, or nil if that was never recorded.
    private var installAge: TimeInterval? {
        guard let stamp = Double(Keychain.get(Key.firstRun) ?? "") else { return nil }
        return Date().timeIntervalSince1970 - stamp
    }

    // MARK: - Trial metering

    var used: Int { Int(Keychain.get(Key.used) ?? "") ?? 0 }

    var remaining: Int { max(0, Self.trialLimit - used) }

    private func stateFor(_ used: Int) -> State {
        if used >= Self.trialLimit { return .trialEnded }
        // An old install with a suspiciously empty counter means the counter was
        // cleared, not that dictation never happened. The trial does not restart.
        if let age = installAge, age > Self.trialWindow, used < Self.trialLimit / 4 {
            return .trialEnded
        }
        return .trial(used: used)
    }

    /// Called after each dictation that produced text. No-op once licensed.
    func recordDictation() {
        guard state != .licensed else { return }
        let total = used + 1
        Keychain.set(String(total), for: Key.used)
        state = stateFor(total)
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
                state = stateFor(used)
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
        state = stateFor(used)
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
