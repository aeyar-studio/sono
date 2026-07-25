import SwiftUI

@main
struct SonoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // The Dock-app window. Closing it keeps the island (and dictation) alive;
        // clicking the Dock icon brings it back.
        Window("Sono", id: "main") {
            DashboardView()
        }
        .defaultSize(width: 980, height: 660)
        // No native title bar: the sidebar runs to the top edge, like a web app.
        .windowStyle(.hiddenTitleBar)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dictation: Dictation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Type.registerBundledFonts()
        ThemeStore.shared.applyDockIcon()   // Dock tile matches the chosen theme
        dictation = Dictation()
    }
}

/// The record → transcribe → clean → polish → paste loop, driving the island.
@MainActor
final class Dictation {
    private let island = Island()
    private let recorder = Recorder()
    private var transcriber: Transcriber = AppleTranscriber()   // replaced by Parakeet in setup
    private var hotkey: Hotkey?
    private var busy = false
    private var modelReady = false
    private var modelError: String?

    init() {
        #if DEBUG
        Cleanup.selfTest()
        Metrics.selfTest()
        #endif
        recorder.onLevel = { [weak self] in self?.island.model.pushLevel($0) }
        island.model.onTap = { [weak self] in self?.toggle() }
        hotkey = Hotkey(
            onToggle: { [weak self] in self?.toggle() },
            onHoldStart: { [weak self] in self?.startForHold() ?? false },
            onHoldEnd: { [weak self] in self?.finishIfRecording() })
        Task { await setup() }
    }

    private func setup() async {
        island.model.phase = .loading("Mic…")
        guard await Recorder.requestMicAccess() else {
            island.model.phase = .flash("Mic denied"); return
        }
        island.model.phase = .loading("Speech…")
        let speechOK = await AppleTranscriber.requestAccess()
        guard speechOK else {
            island.model.phase = .flash("No speech access"); return
        }
        Injector.ensureAccessibility()   // prompts once; paste falls back to copy until granted
        await Licensing.shared.validateIfNeeded()

        // The model is downloaded on first launch — a fresh install must work
        // with no manual setup. Subsequent launches skip straight past this.
        do {
            let paths = try await ModelDownloader.ensureModel { [weak self] stage in
                Task { @MainActor in self?.show(stage) }
            }
            // Building the ONNX sessions blocks for a second or two.
            island.model.phase = .loading("Loading model…")
            if let loaded = await Task.detached(priority: .userInitiated, operation: {
                ParakeetTranscriber(paths: paths)
            }).value {
                transcriber = loaded
                modelReady = true
            } else {
                island.model.phase = .flash("Model failed to load")
                return
            }
        } catch {
            // Tapping the island retries; the dashboard shows the reason too.
            modelError = error.localizedDescription
            island.model.phase = .flash("Model download failed")
            return
        }

        island.model.phase = .ready
    }

    private func show(_ stage: ModelDownloader.Stage) {
        switch stage {
        case .checking:
            island.model.phase = .loading("Checking model…")
        case .downloading(let fraction):
            island.model.phase = .loading("Downloading model \(Int(fraction * 100))%")
        case .verifying:
            island.model.phase = .loading("Verifying model…")
        case .extracting:
            island.model.phase = .loading("Unpacking model…")
        case .ready:
            break
        }
    }

    private func toggle() {
        // A failed first-run download leaves nothing to record with — retry instead.
        if !modelReady {
            Task { await setup() }
            return
        }
        if case .recording = island.model.phase { finish() } else { start() }
    }

    /// Push-to-talk began. Returns whether recording actually started, so the
    /// hotkey knows if the matching release should stop anything.
    private func startForHold() -> Bool {
        guard case .ready = island.model.phase, !busy else { return false }
        start()
        return island.model.phase == .recording
    }

    private func finishIfRecording() {
        if case .recording = island.model.phase { finish() }
    }

    private func start() {
        guard case .ready = island.model.phase, !busy else {
            return
        }
        guard Licensing.shared.state.isUnlocked else {
            flash("Trial ended")
            return
        }
        do {
            island.model.resetLevels()
            Sounds.playStart()          // before the engine: it reconfigures the device
            try recorder.start()
            island.model.phase = .recording
        } catch {
            flash(error.localizedDescription)
        }
    }

    private func finish() {
        island.model.phase = .thinking
        let samples = recorder.stop()
        Sounds.playStop()

        // Under 0.3s is a stray tap, not speech.
        guard samples.count > Int(Recorder.sampleRate * 0.3) else {
            island.model.phase = .ready; return
        }


        busy = true
        Task {
            defer { busy = false }
            do {
                let raw = try await transcriber.transcribe(samples)
                // LLM sees the RAW transcript (strip would eat its correction
                // markers); regex strip runs after, catching missed fillers.
                let text = (Settings.polishEnabled && Polisher.isAvailable)
                    ? Cleanup.strip(await Polisher.polish(raw))
                    : Cleanup.strip(raw)
                let pasted = Injector.paste(text + " ")
                History.shared.add(text: text,
                                   duration: Double(samples.count) / Recorder.sampleRate,
                                   pasted: pasted)
                Licensing.shared.recordDictation(words: Metrics.wordCount(text))
                flash(pasted ? "Pasted" : "Copied to clipboard")
            } catch {
                flash("No speech")
            }
        }
    }

    private func flash(_ message: String) {
        island.model.phase = .flash(message)
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if case .flash = island.model.phase { island.model.phase = .ready }
        }
    }
}
