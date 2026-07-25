import SwiftUI
import AppKit

/// Accent themes. Every colour here was checked with the dataviz palette
/// validator against the surface it actually appears on:
///  - `accent` on the white dashboard (chart bars, active nav, hero)
///  - `island` on the dark pill (#12111B) behind the waveform
/// Light and dark steps are chosen per surface, never auto-derived — the 400
/// tints all failed the dark lightness band, and yellow-500 failed it too,
/// which is why amber uses a deeper step on the pill than in the dashboard.
enum Theme: String, CaseIterable, Identifiable {
    case lavender, terracotta, ochre, moss, dustyRose, burgundy

    var id: String { rawValue }

    var name: String {
        switch self {
        case .lavender: "Lavender"
        case .terracotta: "Terracotta"
        case .ochre: "Ochre"
        case .moss: "Moss"
        case .dustyRose: "Dusty rose"
        case .burgundy: "Burgundy"
        }
    }

    /// Dashboard accent — validated on the cream canvas (#FAF8F3).
    var accentHex: UInt32 {
        switch self {
        case .lavender: 0x8B6DB0
        case .terracotta: 0xC2410C
        case .ochre: 0xA67C00
        case .moss: 0x4D7C0F
        case .dustyRose: 0xC2557A
        case .burgundy: 0xA83250
        }
    }

    /// Island waveform and dark-mode accent — validated on warm dark (#221F1A).
    var islandHex: UInt32 {
        switch self {
        case .lavender: 0x9B7EC4
        case .terracotta: 0xEA580C
        case .ochre: 0xCA8A04
        case .moss: 0x65A30D
        case .dustyRose: 0xDB6A8C
        case .burgundy: 0xC2405E
        }
    }

    /// The mark is a single flat colour now — the chunky bars read cleanest
    /// solid, and a gradient muddies them at 16pt.
    var markHex: UInt32 { accentHex }

    /// Dashboard accent: the white-surface step in light mode, the dark-surface
    /// step in dark mode. Both were validated on the surface they appear on.
    var accent: Color { Color(light: accentHex, dark: islandHex) }
    /// The pill is always dark, so it always uses the dark-validated step.
    var island: Color { Color(hex: islandHex) }
    /// Derived washes — one source of truth, and they work on either canvas.
    var wash: Color { accent.opacity(0.12) }
    var tint: Color { accent.opacity(0.18) }
    /// Swatch for the picker: cream tile with the accent mark, mirroring the icon.
    var swatchGradient: LinearGradient {
        LinearGradient(colors: [Color(hex: accentHex), Color(hex: islandHex)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// Holds the selected theme and pushes it everywhere. Views observe this rather
/// than reading UserDefaults, so a change repaints the dashboard AND the island
/// (both are SwiftUI, even though the island lives in an NSPanel).
@MainActor
final class ThemeStore: ObservableObject {
    static let shared = ThemeStore()

    @Published var theme: Theme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Settings.themeKey)
            applyDockIcon()
        }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: Settings.themeKey) ?? ""
        theme = Theme(rawValue: saved) ?? .lavender
    }

    /// The bundle icon is violet; redraw it so the Dock matches the chosen theme.
    /// Runtime-only — the file on disk is untouched.
    func applyDockIcon() {
        NSApplication.shared.applicationIconImage = IconRenderer.image(for: theme)
    }
}

/// Draws the app icon at runtime with the theme's colours — same construction as
/// Assets/makeicon.swift (squircle, nine bars, gradient), just smaller.
enum IconRenderer {
    /// Redraws the Dock icon in the chosen accent. Same construction as
    /// Assets/makeicon.swift: cream squircle, chunky bars, flat colour.
    static func image(for theme: Theme, size: CGFloat = 512) -> NSImage? {
        guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        func cg(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }

        let inset = size * 0.098
        let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
        let radius = rect.width * 0.235
        let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius,
                              transform: nil)

        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()
        if let tile = CGGradient(colorsSpace: nil,
                                colors: [cg(0xFEFDFA), cg(0xEFEBE1)] as CFArray,
                                locations: [0, 1]) {
            ctx.drawLinearGradient(tile,
                                   start: CGPoint(x: rect.minX, y: rect.maxY),
                                   end: CGPoint(x: rect.maxX, y: rect.minY), options: [])
        }
        ctx.restoreGState()

        // Hairline so the cream tile holds its edge on white backgrounds.
        ctx.addPath(squircle)
        ctx.setStrokeColor(cg(0xE0DACC))
        ctx.setLineWidth(size * 0.006)
        ctx.strokePath()

        let heights: [CGFloat] = [0.09, 0.19, 0.32, 0.19, 0.09]
        let barWidth = rect.width * 0.082
        let gap = rect.width * 0.048
        let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
        var x = size / 2 - total / 2
        for h in heights {
            let barHeight = max(barWidth, rect.width * h)
            let bar = CGRect(x: x, y: size / 2 - barHeight / 2, width: barWidth, height: barHeight)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth / 2,
                               cornerHeight: barWidth / 2, transform: nil))
            // Brand-fixed black; never themed.
            ctx.setFillColor(cg(0x1C1917))
            ctx.fillPath()
            x += barWidth + gap
        }

        guard let cgImage = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
