import Foundation
import ServiceManagement
import AVFoundation
import AppKit
import SwiftUI

@MainActor
final class AppHealthStore: ObservableObject {
    static let shared = AppHealthStore()

    enum PermissionState: Equatable {
        case unknown
        case ready
        case needed
        case denied
    }

    enum ModelState: Equatable {
        case unknown
        case ready
        case loading(String)
        case failed(String)
    }

    @Published var microphone: PermissionState = .unknown
    @Published var accessibility: PermissionState = .unknown
    @Published var model: ModelState = .unknown
    @Published var loginAtStartup: Bool = SMAppService.mainApp.status == .enabled
    @Published var lastError: String?

    private init() {}

    var message: String? {
        if let lastError { return lastError }
        switch (microphone, accessibility, model) {
        case (.denied, _, _):
            return "Mic access needed"
        case (.needed, _, _):
            return "Mic access needed"
        case (_, .needed, _):
            return "Accessibility needed"
        case (_, _, .loading(let message)):
            return message
        case (_, _, .failed(let message)):
            return message
        case (_, _, .ready):
            return nil
        case (_, _, .unknown):
            return nil
        }
    }

    var title: String {
        switch message {
        case .none:
            return "Sono is ready"
        case .some("Mic access needed"):
            return "Microphone access needed"
        case .some("Accessibility needed"):
            return "Accessibility needed"
        case .some(let value):
            return value
        }
    }

    var subtitle: String {
        switch (microphone, accessibility, model) {
        case (.ready, .ready, .ready):
            return "Everything is set up for local dictation."
        case (.denied, _, _), (.needed, _, _):
            return "Sono needs microphone permission before it can listen."
        case (_, .needed, _):
            return "Sono needs Accessibility so it can paste into other apps."
        case (_, _, .loading(let message)):
            return message
        case (_, _, .failed(let message)):
            return message
        default:
            return "The app is checking permissions and model state."
        }
    }

    var iconName: String {
        switch message {
        case .none: return "checkmark.circle.fill"
        case .some("Mic access needed"): return "mic.slash.fill"
        case .some("Accessibility needed"): return "accessibility"
        case .some: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color? {
        switch message {
        case .none: return nil
        default: return .orange
        }
    }

    var needsMic: Bool {
        microphone == .needed || microphone == .denied
    }

    var needsAccessibility: Bool {
        accessibility == .needed
    }

    func refreshPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphone = .ready
        case .notDetermined:
            microphone = .needed
        case .denied, .restricted:
            microphone = .denied
        @unknown default:
            microphone = .needed
        }
        accessibility = AXIsProcessTrusted() ? .ready : .needed
        loginAtStartup = SMAppService.mainApp.status == .enabled
    }

    func setModelLoading(_ message: String) {
        model = .loading(message)
    }

    func setModelReady() {
        model = .ready
    }

    func setModelFailed(_ message: String) {
        model = .failed(message)
        lastError = message
    }

    func syncLoginAtStartup() {
        loginAtStartup = SMAppService.mainApp.status == .enabled
    }
}
