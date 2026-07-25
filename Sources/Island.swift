import SwiftUI
import AppKit

/// What the island shows.
enum IslandPhase: Equatable {
    case loading(String)
    case ready
    case recording
    case thinking
    case flash(String)     // brief note: "Pasted", "No speech"…

    var isRecording: Bool { self == .recording }
}

@MainActor
final class IslandModel: ObservableObject {
    @Published var phase: IslandPhase = .loading("Starting")
    /// Rolling smoothed loudness, newest last — drives the envelope shape.
    static let historyCount = 56
    @Published var levels: [CGFloat] = Array(repeating: 0, count: IslandModel.historyCount)
    private var smoothed: CGFloat = 0
    /// Latest smoothed loudness — what the wave amplitude follows.
    var level: CGFloat { smoothed }
    var onTap: () -> Void = {}

    func pushLevel(_ raw: Float) {
        // Attack fast, release slow: swell instantly on speech, settle gently.
        let target = CGFloat(min(1, max(0, raw)))
        smoothed += (target - smoothed) * (target > smoothed ? 0.5 : 0.14)
        levels.removeFirst()
        levels.append(smoothed)
    }

    func resetLevels() {
        smoothed = 0
        levels = Array(repeating: 0, count: Self.historyCount)
    }
}

/// Hosting view that lets the first click through without activating the app.
/// It also owns the right-click menu: SwiftUI's `.contextMenu` on macOS 26 draws
/// a rounded-RECTANGLE hover highlight that ignores the pill's capsule shape,
/// which showed as a stray square border. An AppKit menu has no such chrome.
private final class FirstMouseHostingView<V: View>: NSHostingView<V> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        wantsLayer = true
        layer?.backgroundColor = .clear
        layer?.masksToBounds = false     // nothing of ours should be cut at the edge
    }

    /// The pill changes size (idle → hover → recording); a window shadow cached
    /// for the previous shape would linger as an outline.
    override func layout() {
        super.layout()
        window?.invalidateShadow()
    }
    override var focusRingType: NSFocusRingType {
        get { .none }
        set { }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Sono", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
            .target = NSApp
        return menu
    }
}

/// The floating island. Window recipe (from voiceflow, in AppKit terms):
///  - .nonactivatingPanel: clicks land, the app never activates, so the text
///    field being dictated into keeps focus and the ⌘V goes there
///  - .screenSaver level, all Spaces + fullscreen
///  - drag anywhere to move; position persisted
@MainActor
final class Island {
    let model = IslandModel()
    private let panel: NSPanel
    // Small: the pill is 26pt tall inside a 34pt window (was 44/56).
    private static let size = NSSize(width: 168, height: 34)

    init() {
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.contentView = FirstMouseHostingView(rootView: IslandView(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true           // window-level, so it can never be clipped
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true

        panel.setFrameAutosaveName("SonoIsland")
        if panel.frame.origin == .zero, let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.midX - Self.size.width / 2, y: f.minY + 6))
        }
        panel.orderFrontRegardless()
    }
}

private struct IslandView: View {
    @ObservedObject var model: IslandModel
    @ObservedObject private var themeStore = ThemeStore.shared
    @State private var hovering = false

    // Idle collapses to a small lozenge and grows on hover.
    private var height: CGFloat {
        switch model.phase {
        case .ready: hovering ? 26 : 15
        case .recording, .thinking: 26
        case .loading, .flash: 24
        }
    }

    /// One accent for every active state. States are told apart by their content
    /// — waveform, dots, text — not by colour, so nothing lands off-palette.
    private var accent: Color {
        switch model.phase {
        case .recording, .thinking, .flash: themeStore.theme.island
        default: Color.white.opacity(0.5)
        }
    }

    var body: some View {
        ZStack {
            // NO SwiftUI .shadow() here, ever. The pill grows on hover, and a
            // blur that extends past the panel's bounds gets clipped into a hard
            // rectangle — that was the "black square border". Depth comes from
            // the window's own shadow (drawn outside the window, unclippable).
            // Solid fill rather than .ultraThinMaterial for the same reason:
            // no NSVisualEffectView painting its own bounds.
            Capsule()
                .fill(Color(red: 0.07, green: 0.065, blue: 0.105).opacity(0.94))
                .overlay(
                    Capsule().fill(
                        LinearGradient(colors: [accent.opacity(0.32), accent.opacity(0.07)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.30), lineWidth: 0.8))

            HStack(spacing: 7) {
                LogoMark(height: model.phase == .recording || hovering ? 13 : 9, onDark: true)
                content
            }
            .padding(.horizontal, 10)
        }
        .frame(width: contentWidth, height: height)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: height)
        .animation(.easeOut(duration: 0.2), value: model.phase)
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture { model.onTap() }
    }

    private var contentWidth: CGFloat {
        switch model.phase {
        case .ready: hovering ? 128 : 44
        case .recording: 142
        case .thinking: 84
        case .loading, .flash: 172
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .ready:
            if hovering {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill").font(.system(size: 9))
                    Text("tap / hold ⌥").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        case .recording:
            WaveLine(level: model.level, color: accent)
        case .thinking:
            BouncingDots()
        case .loading(let message):
            label(message)
        case .flash(let message):
            label(message)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
    }
}

/// The brand mark: five chunky bars, symmetric, outer pair collapsing to dots.
/// Colour is FIXED and does not follow the accent theme: black on light surfaces,
/// cream on dark ones. `onDark` forces cream for the island, which stays dark
/// regardless of the app's appearance setting.
/// That constancy is the point: the UI can be re-themed, the identity cannot.
struct LogoMark: View {
    var height: CGFloat
    /// Set on dark surfaces (the island).
    var onDark = false

    /// Black on light surfaces, cream on dark — resolved per appearance, so the
    /// sidebar mark doesn't disappear in dark mode.
    private static let adaptive = Color(light: 0x1C1917, dark: 0xFAF9F7)
    private static let cream = Color(hex: 0xFAF9F7)
    private static let bars: [CGFloat] = [0.28, 0.58, 1.0, 0.58, 0.28]

    var body: some View {
        // Rounded to whole points: fractional bar widths render soft and turn the
        // outer dots to specks at sidebar/island sizes.
        let barWidth = max(2, (height * 0.25).rounded())
        HStack(spacing: max(2, (height * 0.145).rounded())) {
            ForEach(Self.bars.indices, id: \.self) { i in
                Capsule()
                    .fill(onDark ? Self.cream : Self.adaptive)
                    .frame(width: barWidth,
                           height: max(barWidth, (height * Self.bars[i]).rounded()))
            }
        }
        .frame(height: height)
        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: height)
    }
}

/// Smooth flowing waveform — one continuous line, amplitude from the mic,
/// tapered so it fades flat at both ends.
private struct WaveLine: View {
    let level: CGFloat
    let color: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let mid = size.height / 2
                let amp = mid * 0.9 * max(0.06, level)

                // Two offset sines make the motion organic rather than metronomic.
                func y(_ rel: CGFloat) -> CGFloat {
                    let taper = sin(rel * .pi)                       // 0 at edges, 1 mid
                    let a = sin(rel * .pi * 10 - t * 5.5)
                    let b = sin(rel * .pi * 6.5 - t * 3.4) * 0.45
                    return mid + (a + b) * amp * taper
                }

                var path = Path()
                path.move(to: CGPoint(x: 0, y: mid))
                var x: CGFloat = 0
                while x <= size.width {
                    path.addLine(to: CGPoint(x: x, y: y(x / size.width)))
                    x += 1.5
                }

                context.stroke(path,
                               with: .linearGradient(
                                   Gradient(colors: [color.opacity(0.5), .white, color.opacity(0.5)]),
                                   startPoint: .zero,
                                   endPoint: CGPoint(x: size.width, y: 0)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
        }
        .frame(height: 16)
    }
}

/// Three dots while transcribing.
private struct BouncingDots: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = sin(t * 5 - Double(i) * 0.5)
                    Circle()
                        .fill(.white.opacity(0.5 + 0.5 * phase))
                        .frame(width: 4.5, height: 4.5)
                        .scaleEffect(0.65 + 0.35 * phase)
                }
            }
        }
    }
}
