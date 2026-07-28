import Foundation
import ServiceManagement

@MainActor
final class LoginItemStore: ObservableObject {
    static let shared = LoginItemStore()

    @Published private(set) var enabled: Bool

    private init() {
        enabled = SMAppService.mainApp.status == .enabled
    }

    func syncFromSystem() {
        let systemEnabled = SMAppService.mainApp.status == .enabled
        enabled = systemEnabled
    }

    func setEnabled(_ newValue: Bool) {
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            syncFromSystem()
        } catch {
            syncFromSystem()
        }
    }
}
