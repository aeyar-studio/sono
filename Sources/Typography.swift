import SwiftUI
import AppKit
import CoreText

/// Two bundled families, both SIL OFL (bundling in a commercial product is
/// permitted):
///  - **Plus Jakarta Sans** for every piece of interface text and every number.
///  - **Fraunces** for the wordmark only — a warm serif gives the brand a voice,
///    but display faces have no business in metrics or labels.
enum Type {
    static let family = "Plus Jakarta Sans"
    static let display = "Fraunces"

    /// Registered explicitly rather than trusting Info.plist alone — a wrong
    /// ATSApplicationFontsPath fails silently, which cost us a build looking at
    /// the system font and thinking it was Jakarta.
    static func registerBundledFonts() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts")
            ?? Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil)
            ?? []
        guard !urls.isEmpty else {
            NSLog("Sono: bundled fonts missing, falling back to the system face")
            return
        }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        for expected in [family, display] where !NSFontManager.shared.availableFontFamilies.contains(expected) {
            NSLog("Sono: font family '\(expected)' did not register")
        }
    }

    /// Falls back to the system face if the bundled font is ever missing, so a
    /// packaging mistake degrades quietly instead of crashing.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        NSFontManager.shared.availableFontFamilies.contains(family)
            ? .custom(family, size: size).weight(weight)
            : .system(size: size, weight: weight)
    }

    // Named roles, so sizes live in one place rather than scattered literals.
    static var hero: Font { font(52, .bold) }
    static var figure: Font { font(20, .semibold) }
    static var tileValue: Font { font(21, .semibold) }
    static var pageTitle: Font { font(17, .semibold) }
    static var panelTitle: Font { font(12.5, .semibold) }
    static var body: Font { font(13) }
    static var label: Font { font(11.5) }
    static var caption: Font { font(10.5) }
    static var micro: Font { font(9.5, .semibold) }

    /// The wordmark. Fraunces at a size that holds its own beside the mark.
    static var wordmark: Font {
        NSFontManager.shared.availableFontFamilies.contains(display)
            ? .custom(display, size: 21).weight(.semibold)
            : font(18, .bold)
    }
    static var nav: Font { font(12.5) }
    static var navActive: Font { font(12.5, .semibold) }
}
