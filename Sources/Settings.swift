import SwiftUI

/// User preferences. Read from the dictation loop (not a SwiftUI view), written
/// by the dashboard's @AppStorage bindings — same UserDefaults keys.
enum Settings {
    static let polishKey = "polishEnabled"
    static let engineKey = "polishEngine"
    static let themeKey = "accentTheme"
    static let appearanceKey = "appearance"
    static let soundsKey = "soundsEnabled"
    static let launchAtLoginKey = "launchAtLogin"
    /// Folder holding history.jsonl. Empty = Application Support (local only).
    /// Point it at iCloud Drive to sync across Macs.
    static let historyFolderKey = "historyFolder"
    static let autoUpdateKey = "automaticUpdateChecks"

    /// Off by default. The polish pass is what makes Sono more than a transcript,
    /// but it adds a beat before the text lands, and a first run should feel
    /// instant. Users who want the cleanup turn it on in Settings.
    static var polishEnabled: Bool {
        UserDefaults.standard.object(forKey: polishKey) as? Bool ?? false
    }

    /// Which model does the cleanup.
    ///
    /// Falls back to the old boolean when no engine has been chosen, so anyone
    /// upgrading keeps exactly the behaviour they had: the toggle they switched
    /// on becomes Apple Intelligence, and off stays off.
    static var polishEngine: PolishEngine {
        if let raw = UserDefaults.standard.string(forKey: engineKey),
           let engine = PolishEngine(rawValue: raw) {
            return engine
        }
        return polishEnabled ? .apple : .off
    }

    /// Check for updates in the background, once a day. Default on; the switch
    /// exists because this audience deserves the choice, and a manual check still
    /// works when it is off.
    static var automaticUpdateChecks: Bool {
        UserDefaults.standard.object(forKey: autoUpdateKey) as? Bool ?? true
    }

    /// Chime when dictation starts and stops. Default on.
    static var soundsEnabled: Bool {
        UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? true
    }
}

/// Dashboard appearance. The floating island is always dark — it sits over other
/// people's windows, where a light pill would disappear on light backgrounds.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    /// Light rather than system. The cream palette is the one the app was
    /// designed and tuned in, and it is what someone should meet first;
    /// following the system means a Mac in dark mode shows a face nobody chose.
    static let fallback = Appearance.light

    var id: String { rawValue }
    var name: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
    /// nil follows the system setting.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
