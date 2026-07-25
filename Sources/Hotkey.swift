import Carbon.HIToolbox
import AppKit

/// Global dictation triggers on the left Option key, with two gestures:
///
///  - **Tap** (press and release quickly): toggles. Start now, tap again to
///    stop. For dictating a long passage hands-free.
///  - **Hold**: push-to-talk. Recording begins once the key has been held past
///    `holdThreshold` and stops the moment it's released. For a quick sentence.
///
/// A modifier key rather than an F-key, because with the default macOS setting
/// ("Use F1, F2… as standard function keys" off) a bare F9 is a media key and
/// never reaches any app. F9 stays registered for Macs where it is on, or Fn+F9.
///
/// Both need Accessibility permission, which Sono already requires to paste.
final class Hotkey {
    /// Trigger key code. Left ⌥ = 58, right ⌥ = 61, right ⌘ = 54, Globe/Fn = 63.
    private static let triggerKey = UInt16(58)

    /// Held longer than this and it's push-to-talk rather than a tap.
    private static let holdThreshold: TimeInterval = 0.35

    private let onToggle: () -> Void
    /// Returns true if recording actually started (false if already busy).
    private let onHoldStart: () -> Bool
    private let onHoldEnd: () -> Void

    private var carbonRef: EventHotKeyRef?
    private var monitors: [Any] = []

    /// Gesture state for the current press.
    private var holding = false
    private var contaminated = false
    private var holdTask: DispatchWorkItem?
    private var holdStartedRecording = false

    private static var shared: Hotkey?

    init(onToggle: @escaping () -> Void,
         onHoldStart: @escaping () -> Bool,
         onHoldEnd: @escaping () -> Void) {
        self.onToggle = onToggle
        self.onHoldStart = onHoldStart
        self.onHoldEnd = onHoldEnd
        Hotkey.shared = self
        installModifierMonitors()
        installCarbonF9()
    }

    deinit {
        holdTask?.cancel()
        if let carbonRef { UnregisterEventHotKey(carbonRef) }
        monitors.forEach(NSEvent.removeMonitor)
    }

    // MARK: - Option tap / hold

    private func installModifierMonitors() {
        // Global sees events headed to other apps; local sees our own windows.
        // Both, or the trigger dies whenever Sono's window has focus.
        let mask: NSEvent.EventTypeMask = [
            .flagsChanged, .keyDown,
            .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel,
        ]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        } {
            monitors.append(global)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        if let local { monitors.append(local) }
    }

    private func handle(_ event: NSEvent) {
        // Any keystroke, click, or scroll means Option is being used as a
        // modifier (⌥-click, ⌥-scroll, ⌥+key), not as our trigger.
        if event.type != .flagsChanged {
            if holding { disqualify() }
            return
        }

        if event.keyCode != Self.triggerKey {
            // Another modifier joined the hold.
            if holding { disqualify() }
            return
        }

        event.modifierFlags.contains(.option) ? keyDown(event) : keyUp()
    }

    private func keyDown(_ event: NSEvent) {
        guard !holding else { return }
        let others: NSEvent.ModifierFlags = [.command, .control, .shift]
        guard event.modifierFlags.intersection(others).isEmpty else { return }

        holding = true
        contaminated = false
        holdStartedRecording = false

        // Still held past the threshold? Push-to-talk: start recording now, so
        // speech is captured from the moment the user settles on the key.
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.holding, !self.contaminated else { return }
            self.holdStartedRecording = self.onHoldStart()
        }
        holdTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdThreshold, execute: task)
    }

    private func keyUp() {
        let startedByHold = holdStartedRecording
        let wasContaminated = contaminated
        let wasHolding = holding

        holdTask?.cancel()
        holdTask = nil
        holding = false
        contaminated = false
        holdStartedRecording = false

        guard wasHolding else { return }
        if startedByHold {
            onHoldEnd()                        // released: stop and transcribe
        } else if !wasContaminated {
            onToggle()                         // quick tap: flip recording
        }
    }

    /// Option turned out to be a modifier for something else. A hold that
    /// already started recording still ends cleanly on release; anything that
    /// hasn't started is abandoned.
    private func disqualify() {
        holdTask?.cancel()
        contaminated = true
    }

    // MARK: - F9

    private func installCarbonF9() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            DispatchQueue.main.async { Hotkey.shared?.onToggle() }
            return noErr
        }, 1, &spec, nil, nil)

        let id = EventHotKeyID(signature: OSType(0x534F_4E4F), id: 1)  // 'SONO'
        RegisterEventHotKey(UInt32(kVK_F9), 0, id, GetApplicationEventTarget(), 0, &carbonRef)
    }
}
