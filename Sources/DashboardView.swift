import SwiftUI
import Charts
import AppKit

/// Explicit palette — deliberately NOT system colors. The dashboard should look
/// like a web app (Linear/Vercel register): white canvas, hairline borders,
/// zinc-family ink, one violet accent. System materials and vibrancy are what
/// made it read as generic macOS, so none are used here.
enum Palette {
    // Warm cream system. Light/dark pairs resolve per appearance via a dynamic
    // NSColor, so views just say `Palette.ink`. Dark mode is warm charcoal, not
    // cold zinc — grey-blue darks look dirty beside a cream light mode.
    static let canvas = Color(light: 0xFAF8F3, dark: 0x17150F)
    static let panel = Color(light: 0xFFFEFB, dark: 0x221F1A)
    static let sidebar = Color(light: 0xF2EFE6, dark: 0x120F0A)
    static let border = Color(light: 0xE8E3D7, dark: 0x332E25)
    static let borderSoft = Color(light: 0xF0EDE4, dark: 0x28241D)

    static let ink = Color(light: 0x27251F, dark: 0xF7F4EC)
    static let inkSecondary = Color(light: 0x6B675C, dark: 0xB0A99A)
    static let inkMuted = Color(light: 0x9C978B, dark: 0x7C766A)

    static let warning = Color(light: 0xB45309, dark: 0xFBBF24)
    static let warningWash = Color(light: 0xFDF6E7, dark: 0x2C2205)
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }

    /// A colour that resolves itself for light or dark appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Shell

struct DashboardView: View {
    enum Page: Hashable, CaseIterable {
        case overview, history, settings

        var title: String {
            switch self {
            case .overview: "Overview"
            case .history: "History"
            case .settings: "Settings"
            }
        }
        var subtitle: String {
            switch self {
            case .overview: "Your dictation at a glance"
            case .history: "Everything you've dictated, newest first"
            case .settings: "Appearance and transcription"
            }
        }
        var icon: String {
            switch self {
            case .overview: "square.grid.2x2"
            case .history: "clock"
            case .settings: "slider.horizontal.3"
            }
        }
    }

    @State private var page: Page = .overview
    @AppStorage(Settings.appearanceKey) private var appearanceRaw = Appearance.system.rawValue

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(page: $page)
            Divider().overlay(Palette.border)
            VStack(spacing: 0) {
                PageHeader(page: page)
                Divider().overlay(Palette.borderSoft)
                switch page {
                case .overview: OverviewPage()
                case .history: HistoryList()
                case .settings: SettingsPage()
                }
            }
            .background(Palette.canvas)
        }
        .frame(minWidth: 880, minHeight: 600)
        .preferredColorScheme(Appearance(rawValue: appearanceRaw)?.colorScheme)
    }
}

private struct Sidebar: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    @Binding var page: DashboardView.Page

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Clears the window's traffic lights (title bar is hidden).
            HStack(spacing: 10) {
                LogoMark(height: 19)
                Text("Sono")
                    .font(Type.wordmark)
                    .tracking(-0.2)
                    .foregroundStyle(Palette.ink)
            }
            .padding(.leading, 18)
            .padding(.top, 34)
            .padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(DashboardView.Page.allCases, id: \.self) { item in
                    NavRow(item: item, selected: page == item) { page = item }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            UpdateBanner()
            SidebarFooter()
        }
        .frame(width: 216)
        .background(Palette.sidebar)
    }

    private struct NavRow: View {
        @ObservedObject private var themeStore = ThemeStore.shared
        private var theme: Theme { themeStore.theme }
        let item: DashboardView.Page
        let selected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                HStack(spacing: 9) {
                    Image(systemName: item.icon)
                        .font(Type.font(12, .medium))
                        .frame(width: 16)
                    Text(item.title)
                        .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(selected ? theme.accent : Palette.inkSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(selected ? theme.tint
                                       : (hovering ? Palette.border.opacity(0.55) : .clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
        }
    }
}

private struct PageHeader: View {
    let page: DashboardView.Page
    @ObservedObject private var history = History.shared
    @State private var confirmClear = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(page.title)
                    .font(Type.font(17, .semibold))
                    .foregroundStyle(Palette.ink)
                Text(page.subtitle)
                    .font(Type.font(11.5))
                    .foregroundStyle(Palette.inkSecondary)
            }
            Spacer()
            if page == .history, !history.entries.isEmpty {
                Button {
                    confirmClear = true
                } label: {
                    Text("Clear all")
                        .font(Type.font(11.5, .medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Palette.sidebar))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.border))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Delete all history?", isPresented: $confirmClear) {
                    Button("Delete All", role: .destructive) { history.clear() }
                } message: {
                    Text("This removes every saved dictation. The history never leaves this Mac.")
                }
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 16)
        .background(Palette.canvas)
    }
}

// MARK: - Overview

private struct OverviewPage: View {
    @ObservedObject private var history = History.shared

    private var metrics: Metrics { Metrics(entries: history.entries) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if history.entries.isEmpty {
                    EmptyState()
                } else {
                    HeroRow(metrics: metrics)
                    if metrics.pasteRate < 1 { PasteNotice(rate: metrics.pasteRate) }
                    ActivityCard(metrics: metrics)
                    StatRow(metrics: metrics)
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .frame(maxWidth: 1160, alignment: .leading)
            // Full-width scroll area keeps the scrollbar at the window edge; the
            // block inside is centred, so a wide window doesn't strand the
            // content against the sidebar.
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.canvas)
    }
}

/// One hero figure (time saved) plus the two headline totals.
private struct HeroRow: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    let metrics: Metrics

    var body: some View {
        HStack(spacing: 14) {
            Panel {
                VStack(alignment: .leading, spacing: 0) {
                    Label {
                        Text("Time saved")
                            .font(Type.font(11.5, .medium))
                    } icon: {
                        Image(systemName: "bolt.fill").font(Type.font(10))
                    }
                    .foregroundStyle(theme.accent)

                    Text(Metrics.duration(metrics.timeSaved))
                        .font(Type.font(54, .bold))
                        .tracking(-1.4)
                        .monospacedDigit()
                        .foregroundStyle(Palette.ink)
                        .padding(.top, 10)

                    Text("versus typing the same words at \(Int(Metrics.typingWPM)) wpm")
                        .font(Type.font(11))
                        .foregroundStyle(Palette.inkMuted)
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
            .background(
                // A whisper of accent so the hero panel leads without shouting.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(LinearGradient(colors: [theme.wash, Palette.panel],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.border))

            VStack(spacing: 14) {
                Totals(label: "Words dictated", value: Metrics.count(metrics.words), icon: "text.word.spacing")
                Totals(label: "Time spoken", value: Metrics.duration(metrics.spoken), icon: "waveform")
            }
            .frame(width: 214)
        }
    }

    private struct Totals: View {
        @ObservedObject private var themeStore = ThemeStore.shared
        private var theme: Theme { themeStore.theme }
        let label: String
        let value: String
        let icon: String

        var body: some View {
            Panel(padding: 15) {
                HStack(spacing: 11) {
                    Image(systemName: icon)
                        .font(Type.font(12, .medium))
                        .foregroundStyle(theme.accent)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(theme.wash))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(value)
                            .font(Type.font(19, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                        Text(label)
                            .font(Type.font(10.5))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

/// Words per day, 14 days. Single series → one hue for every bar, no legend, no
/// value-ramp. Hover a bar and the header becomes that day's readout.
private struct ActivityCard: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    let metrics: Metrics
    @State private var selected: Date?

    private var selectedDay: Metrics.Day? {
        guard let selected else { return nil }
        return metrics.daily.min {
            abs($0.date.timeIntervalSince(selected)) < abs($1.date.timeIntervalSince(selected))
        }
    }

    private var total: Int { metrics.daily.reduce(0) { $0 + $1.words } }
    private var busiest: Metrics.Day? { metrics.daily.max { $0.words < $1.words } }

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Words per day")
                            .font(Type.font(12.5, .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("Last 14 days")
                            .font(Type.font(10.5))
                            .foregroundStyle(Palette.inkMuted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Metrics.count(selectedDay?.words ?? total))
                            .font(Type.font(19, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                        Text(selectedDay.map { $0.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)) }
                             ?? "words in total")
                            .font(Type.font(10.5))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                }

                Chart(metrics.daily) { day in
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Words", day.words),
                        width: .fixed(13)            // ≤24pt; the band's leftover is air
                    )
                    .cornerRadius(4)                 // rounded data-end
                    .foregroundStyle(theme.accent.opacity(
                        selectedDay == nil || selectedDay?.id == day.id ? 1 : 0.28))
                    // Selective direct label: only the busiest day gets a number.
                    .annotation(position: .top, spacing: 5) {
                        if selectedDay == nil, day.id == busiest?.id, day.words > 0 {
                            Text(Metrics.count(day.words))
                                .font(Type.font(9.5, .medium))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .chartXSelection(value: $selected)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) {
                        AxisGridLine().foregroundStyle(Palette.borderSoft)   // hairline, solid
                        AxisValueLabel()
                            .font(Type.font(9.5))
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: 2)) {
                        AxisValueLabel(format: .dateTime.day(), centered: true)
                            .font(Type.font(9.5))
                            .foregroundStyle(Palette.inkMuted)
                    }
                }
                .frame(height: 150)
            }
        }
    }
}

private struct StatRow: View {
    let metrics: Metrics

    var body: some View {
        HStack(spacing: 14) {
            Tile(label: "Speaking rate", value: "\(Int(metrics.wordsPerMinute.rounded()))", unit: "wpm")
            Tile(label: "Dictations", value: Metrics.count(metrics.dictations), unit: nil)
            Tile(label: "Average length", value: Metrics.shortDuration(metrics.averageLength), unit: nil)
            Tile(label: "Characters", value: Metrics.count(metrics.characters), unit: nil)
        }
    }

    private struct Tile: View {
        let label: String
        let value: String
        let unit: String?

        var body: some View {
            Panel(padding: 15) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(label.uppercased())
                        .font(Type.font(9.5, .semibold))
                        .tracking(0.5)
                        .foregroundStyle(Palette.inkMuted)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(value)
                            .font(Type.font(20, .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Palette.ink)
                        if let unit {
                            Text(unit)
                                .font(Type.font(10.5, .medium))
                                .foregroundStyle(Palette.inkSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Shown only when pastes are failing — a health check, not a vanity stat.
private struct PasteNotice: View {
    let rate: Double

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(Type.font(11))
                .foregroundStyle(Palette.warning)
            Text("\(Int(((1 - rate) * 100).rounded()))% of dictations were copied but not pasted. Grant Sono Accessibility access in System Settings to paste automatically.")
                .font(Type.font(11))
                .foregroundStyle(Palette.warning)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9).fill(Palette.warningWash))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.warning.opacity(0.18)))
    }
}

private struct PolishRow: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    private var theme: Theme { themeStore.theme }
    @Binding var enabled: Bool

    private var subtitle: String {
        guard Polisher.isAvailable else {
            return "Unavailable. Turn on Apple Intelligence in System Settings"
        }
        return enabled
            ? "Fixes self-corrections and grammar · adds about a second"
            : "Off. Raw transcription, fastest output"
    }

    var body: some View {
        Panel(padding: 15) {
            HStack(spacing: 12) {
                Image(systemName: "wand.and.sparkles")
                    .font(Type.font(12, .medium))
                    .foregroundStyle(enabled && Polisher.isAvailable ? theme.accent : Palette.inkMuted)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(enabled && Polisher.isAvailable ? theme.wash : Palette.sidebar))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Enhance with Apple Intelligence")
                        .font(Type.font(12, .medium))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(Type.font(10.5))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $enabled)
                    .toggleStyle(.switch)
                    .tint(theme.accent)
                    .labelsHidden()
                    .disabled(!Polisher.isAvailable)
            }
        }
    }
}

private struct EmptyState: View {
    var body: some View {
        Panel(padding: 34) {
            VStack(alignment: .leading, spacing: 9) {
                LogoMark(height: 20)
                Text("No dictations yet")
                    .font(Type.font(15, .semibold))
                    .foregroundStyle(Palette.ink)
                Text("Click into any text field, then tap ⌥ to start and stop, or hold ⌥ and speak. Your metrics will appear here.")
                    .font(Type.font(12))
                    .foregroundStyle(Palette.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 380, alignment: .leading)
        }
    }
}

/// The one surface treatment: white, hairline border, 12pt radius. No shadows,
/// no materials — that flatness is what keeps it looking like a web dashboard.
struct Panel<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.panel))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.border))
    }
}

// MARK: - Settings

private struct SettingsPage: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    @AppStorage(Settings.polishKey) private var polishEnabled = true
    @AppStorage(Settings.appearanceKey) private var appearanceRaw = Appearance.system.rawValue
    @AppStorage(Settings.soundsKey) private var soundsEnabled = true
    private var theme: Theme { themeStore.theme }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Group {
                    SettingsSection("Appearance", note: nil) {
                        AppearancePicker(selection: $appearanceRaw)
                    }
                    SettingsSection("Accent",
                                    note: "Applies everywhere: dashboard, the floating island, the logo and the Dock icon.") {
                        ThemePicker()
                    }
                    SettingsSection("Transcription",
                                    note: "Turning enhancement off skips the language model, so text appears sooner.") {
                        VStack(spacing: 8) {
                            PolishRow(enabled: $polishEnabled)
                            ToggleRow(icon: "speaker.wave.2",
                                      title: "Start and stop chime",
                                      detail: "A short tone when dictation begins and ends",
                                      isOn: $soundsEnabled)
                        }
                    }
                    SettingsSection("History",
                                    note: "Metrics are calculated from this file, so moving it carries them too.") {
                        HistoryLocationRow()
                    }
                    SettingsSection("Shortcut", note: nil) {
                        InfoRow(icon: "keyboard",
                                title: "Tap ⌥ to start and stop",
                                detail: "Hold ⌥ instead for push-to-talk, so recording ends when you let go. F9 also works if your F-keys are set to standard function keys.")
                    }
                    SettingsSection("Engine", note: nil) {
                        InfoRow(icon: "cpu",
                                title: "Parakeet TDT 0.6B v3 · on-device",
                                detail: "Speech recognition and enhancement both run locally. Audio never leaves this Mac.")
                    }
                    SettingsSection("Licence", note: nil) {
                        LicenceRow()
                    }
                    SettingsSection("Updates", note: nil) {
                        UpdateRow()
                    }
                    SettingsSection("Uninstall",
                                    note: "Dragging Sono to the Trash removes only the app. The model and your history would stay on disk.") {
                        RemoveDataRow()
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 22)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Palette.canvas)
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let note: String?
    @ViewBuilder var content: Content

    init(_ title: String, note: String?, @ViewBuilder content: () -> Content) {
        self.title = title
        self.note = note
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Type.font(9.5, .semibold))
                .tracking(0.6)
                .foregroundStyle(Palette.inkMuted)
                .padding(.leading, 2)
            content
            if let note {
                Text(note)
                    .font(Type.font(10.5))
                    .foregroundStyle(Palette.inkMuted)
                    .padding(.leading, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ThemePicker: View {
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        Panel(padding: 16) {
            HStack(spacing: 10) {
                ForEach(Theme.allCases) { option in
                    Swatch(theme: option, selected: themeStore.theme == option) {
                        withAnimation(.easeOut(duration: 0.18)) { themeStore.theme = option }
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private struct Swatch: View {
        let theme: Theme
        let selected: Bool
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                VStack(spacing: 7) {
                    ZStack {
                        Circle()
                            .fill(theme.swatchGradient)
                            .frame(width: 30, height: 30)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(Type.font(12, .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    // Selection ring sits outside the swatch so the colour stays true.
                    .padding(3)
                    .overlay(
                        Circle().strokeBorder(selected ? theme.accent : .clear, lineWidth: 1.5)
                    )
                    .scaleEffect(hovering && !selected ? 1.06 : 1)

                    Text(theme.name)
                        .font(.system(size: 10, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Palette.ink : Palette.inkSecondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help(theme.name)
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let title: String
    let detail: String
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        Panel(padding: 15) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(Type.font(12, .medium))
                    .foregroundStyle(themeStore.theme.accent)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(themeStore.theme.wash))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(Type.font(12, .medium))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(Type.font(10.5))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// Light / Dark / System, as a segmented row of cards. The island is exempt —
/// it always stays dark because it floats over other apps' windows.
private struct AppearancePicker: View {
    @Binding var selection: String
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        Panel(padding: 10) {
            HStack(spacing: 8) {
                ForEach(Appearance.allCases) { option in
                    let active = selection == option.rawValue
                    Button {
                        withAnimation(.easeOut(duration: 0.16)) { selection = option.rawValue }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: option.icon)
                                .font(Type.font(11, .medium))
                            Text(option.name)
                                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                        }
                        .foregroundStyle(active ? themeStore.theme.accent : Palette.inkSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(active ? themeStore.theme.tint : Palette.borderSoft.opacity(0.6)))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(active ? themeStore.theme.accent.opacity(0.35) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// A settings row that is just a labelled switch.
private struct ToggleRow: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var isOn: Bool
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        Panel(padding: 15) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(Type.font(12, .medium))
                    .foregroundStyle(isOn ? themeStore.theme.accent : Palette.inkMuted)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? themeStore.theme.wash : Palette.borderSoft))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Type.font(12, .medium))
                        .foregroundStyle(Palette.ink)
                    Text(detail)
                        .font(Type.font(10.5))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .tint(themeStore.theme.accent)
                    .labelsHidden()
            }
        }
    }
}

/// Where history.jsonl lives. Pointing it at iCloud Drive is how syncing works —
/// Apple does the syncing, Sono just writes a file there.
private struct HistoryLocationRow: View {
    @ObservedObject private var themeStore = ThemeStore.shared
    @ObservedObject private var history = History.shared
    @AppStorage(Settings.historyFolderKey) private var folderPath = ""

    private var theme: Theme { themeStore.theme }
    private var isDefault: Bool { folderPath.isEmpty }

    var body: some View {
        Panel(padding: 15) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: History.isSynced ? "icloud" : "internaldrive")
                        .font(Type.font(12, .medium))
                        .foregroundStyle(History.isSynced ? theme.accent : Palette.inkMuted)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(History.isSynced ? theme.wash : Palette.borderSoft))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(History.isSynced ? "Syncing across your Macs" : "This Mac only")
                            .font(Type.font(12, .medium))
                            .foregroundStyle(Palette.ink)
                        Text(displayPath)
                            .font(Type.font(10.5))
                            .foregroundStyle(Palette.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                }

                HStack(spacing: 7) {
                    if let iCloud = History.iCloudDriveFolder, !History.isSynced {
                        SmallButton(title: "Use iCloud Drive", filled: true) {
                            history.move(to: iCloud.appendingPathComponent("Sono"))
                        }
                    }
                    SmallButton(title: "Choose folder…", filled: false) { pickFolder() }
                    if !isDefault {
                        SmallButton(title: "Keep on this Mac", filled: false) {
                            history.resetLocation()
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var displayPath: String {
        let path = History.file.path
        return path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.message = "Choose where Sono keeps its history file."
        if panel.runModal() == .OK, let url = panel.url {
            history.move(to: url)
        }
    }
}

/// The uninstall helper: removes the model, the history and the preferences,
/// then quits. Two confirmations, because it deletes a 640 MB download too.
private struct RemoveDataRow: View {
    @State private var confirming = false
    @State private var inventory: DataRemoval.Inventory?

    var body: some View {
        Panel(padding: 15) {
            HStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(Type.font(12, .medium))
                    .foregroundStyle(Palette.warning)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Palette.warningWash))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Remove all Sono data")
                        .font(Type.font(12, .medium))
                        .foregroundStyle(Palette.ink)
                    Text(subtitle)
                        .font(Type.font(10.5))
                        .foregroundStyle(Palette.inkSecondary)
                }
                Spacer(minLength: 12)
                SmallButton(title: "Remove…", filled: false, destructive: true) {
                    inventory = DataRemoval.inventory()
                    confirming = true
                }
            }
        }
        .confirmationDialog("Remove all Sono data?", isPresented: $confirming) {
            Button("Delete \(inventory?.readableTotal ?? "everything") and Quit", role: .destructive) {
                DataRemoval.removeEverythingAndQuit()
            }
        } message: {
            Text("""
                 This deletes the speech model (\(inventory?.readableModel ?? "unknown")), \
                 your dictation history and all preferences, then quits Sono. \
                 Afterwards, drag Sono to the Trash to finish uninstalling.

                 This cannot be undone.
                 """)
        }
    }

    private var subtitle: String {
        let inv = DataRemoval.inventory()
        return "Model, history and preferences · \(inv.readableTotal) on disk"
    }
}

/// Compact web-style button used by the settings rows.
private struct SmallButton: View {
    let title: String
    let filled: Bool
    var destructive = false
    let action: () -> Void
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Type.font(11, .medium))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5.5)
                .background(RoundedRectangle(cornerRadius: 7).fill(background))
                .overlay(RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(filled ? .clear : Palette.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var foreground: Color {
        if filled { return .white }
        return destructive ? Palette.warning : Palette.inkSecondary
    }

    private var background: Color {
        if filled { return themeStore.theme.accent.opacity(hovering ? 0.85 : 1) }
        return hovering ? Palette.borderSoft : .clear
    }
}

/// Trial progress, or licence status with a key field. Shown in Settings, and
/// surfaced on the Overview once the trial is nearly spent.
private struct LicenceRow: View {
    @ObservedObject private var licensing = Licensing.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var key = ""
    @State private var showingDeactivate = false

    private var theme: Theme { themeStore.theme }

    var body: some View {
        Panel(padding: 15) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(licensing.state == .licensed ? theme.accent : Palette.inkMuted)
                        .frame(width: 28, height: 28)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(licensing.state == .licensed ? theme.wash : Palette.borderSoft))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(Type.font(12, .medium))
                            .foregroundStyle(Palette.ink)
                        Text(subtitle)
                            .font(Type.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    if licensing.state == .licensed {
                        SmallButton(title: "Deactivate this Mac", filled: false) {
                            showingDeactivate = true
                        }
                    }
                }

                if case .licensed = licensing.state {} else {
                    // Trial meter: the same "time saved" idea, but showing what's left.
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Palette.borderSoft)
                            Capsule().fill(theme.accent)
                                .frame(width: geometry.size.width * progress)
                        }
                    }
                    .frame(height: 5)

                    HStack(spacing: 8) {
                        TextField("Licence key", text: $key)
                            .textFieldStyle(.plain)
                            .font(Type.font(11.5))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Palette.canvas))
                            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.border))
                            .onSubmit { Task { await licensing.activate(key: key) } }
                        SmallButton(title: licensing.isWorking ? "Checking…" : "Activate", filled: true) {
                            Task { await licensing.activate(key: key) }
                        }
                        Link(destination: URL(string: Licensing.buyURL)!) {
                            Text("Buy · $39")
                                .font(Type.font(11, .medium))
                                .foregroundStyle(theme.accent)
                        }
                    }

                    if let error = licensing.lastError {
                        Text(error)
                            .font(Type.caption)
                            .foregroundStyle(Palette.warning)
                    }
                }
            }
        }
        .confirmationDialog("Deactivate Sono on this Mac?", isPresented: $showingDeactivate) {
            Button("Deactivate", role: .destructive) {
                Task { await licensing.deactivateThisMac() }
            }
        } message: {
            Text("This frees the activation so you can use your key on another Mac. Dictation stops working here until you activate again.")
        }
    }

    private var progress: Double {
        Double(licensing.used) / Double(Licensing.trialLimit)
    }

    private var icon: String {
        switch licensing.state {
        case .licensed: "checkmark.seal"
        case .trialEnded: "lock"
        case .trial: "hourglass"
        }
    }

    private var title: String {
        switch licensing.state {
        case .licensed: "Licensed"
        case .trialEnded: "Trial ended"
        case .trial: "Free trial"
        }
    }

    private var subtitle: String {
        switch licensing.state {
        case .licensed: "Thank you. This Mac is activated"
        case .trialEnded: "Enter your key to keep dictating"
        case .trial:
            "\(licensing.remaining) of \(Licensing.trialLimit) free dictations left, then $39 once"
        }
    }
}

/// The bottom of the sidebar. Once someone has paid, this is the one place the
/// app says thank you — so it uses the display face and warm wording rather than
/// restating a feature. Before that, it quietly shows what's left of the trial.
private struct SidebarFooter: View {
    @ObservedObject private var licensing = Licensing.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var appeared = false

    private var theme: Theme { themeStore.theme }

    var body: some View {
        Group {
            switch licensing.state {
            case .licensed: licensed
            case .trial: trial
            case .trialEnded: ended
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.wash)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.14)))
        )
        .padding(12)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) { appeared = true }
        }
    }

    private var licensed: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.accent)
                    .scaleEffect(appeared ? 1 : 0.6)
                    .opacity(appeared ? 1 : 0)
                Text("Sono is yours")
                    .font(Type.font(14, .semibold))
                    .foregroundStyle(Palette.ink)
            }
            Text("Yours for good. No subscription, no expiry.")
                .font(Type.caption)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trial: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Free trial")
                .font(Type.font(11, .semibold))
                .foregroundStyle(theme.accent)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(theme.accent.opacity(0.16))
                    Capsule().fill(theme.accent)
                        .frame(width: geometry.size.width * progress)
                }
            }
            .frame(height: 4)
            Text("\(licensing.remaining) of \(Licensing.trialLimit) dictations left")
                .font(Type.caption)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private var ended: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Trial ended")
                .font(Type.font(11, .semibold))
                .foregroundStyle(Palette.warning)
            Text("Add your licence in Settings to keep dictating.")
                .font(Type.caption)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var progress: Double {
        min(1, Double(licensing.used) / Double(Licensing.trialLimit))
    }
}

/// Sits above the licence footer when a newer version exists. This is the entry
/// point people described wanting: noticed in place, not a modal that steals focus.
private struct UpdateBanner: View {
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var themeStore = ThemeStore.shared

    var body: some View {
        if let version = updater.availableVersion {
            Button {
                updater.checkForUpdates()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(themeStore.theme.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Version \(version) is ready")
                            .font(Type.font(11.5, .semibold))
                            .foregroundStyle(Palette.ink)
                        Text("Click to update and relaunch")
                            .font(Type.font(10))
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(themeStore.theme.tint))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
        }
    }
}

private struct UpdateRow: View {
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var themeStore = ThemeStore.shared
    @AppStorage(Settings.autoUpdateKey) private var automatic = true

    var body: some View {
        VStack(spacing: 8) {
            ToggleRow(icon: "arrow.triangle.2.circlepath",
                      title: "Check for updates automatically",
                      detail: "Once a day. Sono sends only its version number, never your text.",
                      isOn: $automatic)
            Panel(padding: 15) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(updater.currentVersion)")
                            .font(Type.font(12, .medium))
                            .foregroundStyle(Palette.ink)
                        Text(status)
                            .font(Type.caption)
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    Spacer(minLength: 12)
                    SmallButton(title: "Check now", filled: false) {
                        updater.checkForUpdates()
                    }
                }
            }
        }
        .onChange(of: automatic) { _, newValue in updater.automaticChecks = newValue }
    }

    private var status: String {
        if let version = updater.availableVersion { return "Version \(version) is available" }
        if let checked = updater.lastChecked {
            return "Last checked \(checked.formatted(.relative(presentation: .named)))"
        }
        return "Not checked yet"
    }
}
