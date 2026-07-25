import AppKit

/// Paste into whatever app has focus: clipboard + synthetic ⌘V.
/// voiceflow's clipboard etiquette applied:
///  - restore whatever was on the clipboard, not just text. Restoring only the
///    string silently destroyed screenshots, copied files and rich text, because
///    clearContents() drops every representation and only the string came back.
///  - restore ONLY if nobody wrote to the clipboard meanwhile, checked by
///    changeCount rather than by comparing strings, which cannot tell our own
///    text apart from the user copying the same text during the paste window
///  - if the keystroke can't be sent (no Accessibility), leave the transcript
///    on the clipboard so the user can paste manually, never restore over it
enum Injector {
    /// Between writing the clipboard and pressing ⌘V. Native apps see the new
    /// pasteboard immediately, but Electron, Java and anything inside a VM or a
    /// remote session read through their own clipboard layer and can be a beat
    /// behind, in which case ⌘V pastes whatever was there *before* the
    /// transcript. Slack, VS Code and most terminals are in that category, which
    /// is exactly what Sono is used in. 25 ms is below the threshold of notice.
    private static let settleDelay = 0.025

    /// Between ⌘V and putting the old clipboard back. ⌘V is fire and forget: the
    /// other app reads the pasteboard whenever it gets to the event, so restoring
    /// too early means it reads the restored content and pastes that instead.
    private static let restoreDelay = 0.8

    /// The app about to receive the paste, for the per-app breakdown on the
    /// dashboard. Safe to read right up to the keystroke: the island is a
    /// non-activating panel, so Sono never becomes frontmost and this stays the
    /// real destination. Returns nil for Sono itself, which is not a place
    /// anyone dictates into and would only add noise to the numbers.
    static func target() -> (name: String, bundleID: String)? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier else { return nil }
        return (app.localizedName ?? bundleID, bundleID)
    }

    @discardableResult
    static func ensureAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns true if the paste keystroke was sent, false if only copied.
    @discardableResult
    static func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general

        // Plain text is the overwhelmingly common case and costs nothing to hold
        // on to. Everything else needs every representation copied out, which for
        // a screenshot is megabytes, so only pay for that when there is no string.
        let previousText = pasteboard.string(forType: .string)
        let previousItems = previousText == nil ? snapshot(pasteboard) : []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        guard AXIsProcessTrusted() else { return false }   // stays on clipboard

        // Deferred rather than slept through: this runs on the main queue, and
        // blocking it even briefly would stutter the island animation.
        DispatchQueue.main.asyncAfter(deadline: .now() + settleDelay) {
            pressCommandV()

            DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
                // Someone else has written since we did; their content wins.
                guard pasteboard.changeCount == ourChangeCount else { return }
                restore(text: previousText, items: previousItems, to: pasteboard)
            }
        }
        return true
    }

    /// A deep copy of everything on the pasteboard. NSPasteboardItem instances
    /// belonging to a pasteboard are invalidated by clearContents(), so the data
    /// has to be pulled out eagerly rather than by holding references.
    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private static func restore(text: String?, items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        if let text {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        } else if !items.isEmpty {
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
        // Nothing was there before. Leave the transcript rather than clearing:
        // if the ⌘V silently failed, the clipboard is the user's only copy of
        // what they just said.
    }

    private static func pressCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let v = CGKeyCode(9)
        let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    #if DEBUG
    /// Runs against a private named pasteboard, never the user's general one.
    static func selfTest() {
        let board = NSPasteboard(name: .init("app.heysono.injector.selftest"))
        defer { board.releaseGlobally() }

        // A screenshot on the clipboard: no string, one image representation.
        let png = NSImage(size: NSSize(width: 2, height: 2))
        png.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 2, height: 2).fill()
        png.unlockFocus()
        guard let tiff = png.tiffRepresentation else { return }

        board.clearContents()
        let original = NSPasteboardItem()
        original.setData(tiff, forType: .tiff)
        board.writeObjects([original])

        let text = board.string(forType: .string)
        let items = text == nil ? snapshot(board) : []
        assert(text == nil, "an image-only clipboard has no string")
        assert(!items.isEmpty, "the image must be captured before clearContents")

        board.clearContents()
        board.setString("dictated text", forType: .string)
        assert(board.data(forType: .tiff) == nil, "the image is gone once overwritten")

        restore(text: text, items: items, to: board)
        assert(board.data(forType: .tiff) == tiff, "the image must come back byte for byte")
        assert(board.string(forType: .string) == nil, "and the transcript must not linger")

        // The ordinary text case still round-trips.
        board.clearContents()
        board.setString("before", forType: .string)
        let priorText = board.string(forType: .string)
        board.clearContents()
        board.setString("dictated", forType: .string)
        restore(text: priorText, items: [], to: board)
        assert(board.string(forType: .string) == "before")

        print("Injector.selfTest ok")
    }
    #endif
}
