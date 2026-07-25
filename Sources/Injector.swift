import AppKit

/// Paste into whatever app has focus: clipboard + synthetic ⌘V.
/// voiceflow's clipboard etiquette applied:
///  - restore the old clipboard ONLY if it still holds our text (nobody else
///    wrote to it meanwhile)
///  - if the keystroke can't be sent (no Accessibility), leave the transcript
///    on the clipboard so the user can paste manually — never restore over it
enum Injector {
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Returns true if the paste keystroke was sent, false if only copied.
    @discardableResult
    static func paste(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else { return false }   // stays on clipboard
        pressCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if pasteboard.string(forType: .string) == text, let previous {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
        return true
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
}
