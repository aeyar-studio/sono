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
        LoginItemStore.shared.syncFromSystem()
        AppHealthStore.shared.refreshPermissions()
        dictation = Dictation()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        AppHealthStore.shared.refreshPermissions()
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
        Injector.selfTest()
        VoiceActivity.selfTest()
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
        AppHealthStore.shared.setModelLoading("Checking permissions…")
        island.model.phase = .loading("Mic…")
        AppHealthStore.shared.refreshPermissions()
        guard await Recorder.requestMicAccess() else {
            AppHealthStore.shared.setModelFailed("Microphone access needed")
            island.model.phase = .flash("Mic denied"); return
        }
        // No Speech Recognition request: transcription is Parakeet via sherpa-onnx,
        // and Apple's recogniser is never reached on the shipping path. Asking for
        // a permission the app does not use is a poor look for one that promises
        // nothing leaves the Mac.

        // Accessibility asked for here, next to the microphone, so both are
        // settled before the user starts working. macOS cannot grant it in place
        // and opens System Settings, which is disruptive wherever it happens, so
        // it belongs in setup rather than interrupting someone mid-sentence.
        Injector.ensureAccessibility()
        AppHealthStore.shared.refreshPermissions()

        // The model is downloaded on first launch — a fresh install must work
        // with no manual setup. Subsequent launches skip straight past this.
        do {
            AppHealthStore.shared.setModelLoading("Downloading model…")
            let paths = try await ModelDownloader.ensureModel { [weak self] stage in
                Task { @MainActor in
                    AppHealthStore.shared.setModelLoading({
                        switch stage {
                        case .checking: return "Checking model…"
                        case .downloading(let fraction): return "Downloading model \(Int(fraction * 100))%"
                        case .verifying: return "Verifying model…"
                        case .extracting: return "Unpacking model…"
                        case .ready: return "Loading model…"
                        }
                    }())
                    self?.show(stage)
                }
            }
            // Building the ONNX sessions blocks for a second or two.
            island.model.phase = .loading("Loading model…")
            if let loaded = await Task.detached(priority: .userInitiated, operation: {
                ParakeetTranscriber(paths: paths)
            }).value {
                transcriber = loaded
                modelReady = true
                AppHealthStore.shared.setModelReady()
            } else {
                AppHealthStore.shared.setModelFailed("Model failed to load")
                island.model.phase = .flash("Model failed to load")
                return
            }
        } catch {
            // Tapping the island retries; the dashboard shows the reason too.
            modelError = error.localizedDescription
            AppHealthStore.shared.setModelFailed(error.localizedDescription)
            island.model.phase = .flash("Model download failed")
            return
        }

        island.model.phase = .ready
    }

    private func show(_ stage: ModelDownloader.Stage) {
        switch stage {
        case .checking:
            AppHealthStore.shared.setModelLoading("Checking model…")
            island.model.phase = .loading("Checking model…")
        case .downloading(let fraction):
            AppHealthStore.shared.setModelLoading("Downloading model \(Int(fraction * 100))%")
            island.model.phase = .loading("Downloading model \(Int(fraction * 100))%")
        case .verifying:
            AppHealthStore.shared.setModelLoading("Verifying model…")
            island.model.phase = .loading("Verifying model…")
        case .extracting:
            AppHealthStore.shared.setModelLoading("Unpacking model…")
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
        do {
            island.model.resetLevels()
            Sounds.playStart()          // before the engine: it reconfigures the device
            try recorder.start()
            island.model.phase = .recording
        } catch {
            AppHealthStore.shared.setModelFailed(error.localizedDescription)
            flash(error.localizedDescription)
        }
    }

    private func finish() {
        island.model.phase = .thinking
        let samples = recorder.stop()
        Sounds.playStop()

        // Drop the quiet off both ends, and drop the recording entirely if nobody
        // spoke. Replaces a flat 0.3s duration guard, which could not tell a long
        // silence from a long sentence: the model was billed for leading quiet,
        // and room tone alone could still come back as a word.
        guard let speech = VoiceActivity.trim(samples) else {
            AppHealthStore.shared.setModelReady()
            island.model.phase = .ready; return
        }

        busy = true
        Task {
            defer { busy = false }
            do {
                let raw = try await transcriber.transcribe(speech)
                // LLM sees the RAW transcript (strip would eat its correction
                // markers); regex strip runs after, catching missed fillers.
                let engine = Settings.polishEngine
                let text = Polish.isAvailable(engine)
                    ? Cleanup.strip(await Polish.run(raw, using: engine))
                    : Cleanup.strip(raw)
                // Read before the paste, while the target is still frontmost.
                let target = Injector.target()
                let pasted = Injector.paste(text + " ")
                // Trimmed length, not raw: "time spoken" should mean time spoken,
                // not how long the key was held.
                History.shared.add(text: text,
                                   duration: Double(speech.count) / Recorder.sampleRate,
                                   pasted: pasted,
                                   app: target?.name, appID: target?.bundleID)
                AppHealthStore.shared.lastError = nil
                flash(pasted ? "Pasted" : "Copied to clipboard")
            } catch {
                AppHealthStore.shared.setModelFailed("No speech")
                flash("No speech")
            }
        }
    }

    private func flash(_ message: String) {
        island.model.phase = .flash(message)
        if message != "Pasted" && message != "Copied to clipboard" {
            AppHealthStore.shared.lastError = message
        }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            if case .flash = island.model.phase { island.model.phase = .ready }
        }
    }
}
