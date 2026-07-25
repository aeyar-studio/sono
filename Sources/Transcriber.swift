import AVFoundation
import Speech

enum SonoError: Error { case recognizerUnavailable, noAudio, localeUnsupported }

protocol Transcriber {
    func transcribe(_ samples: [Float]) async throws -> String
}

/// macOS 26 SpeechAnalyzer/SpeechTranscriber: on-device, and crucially it can
/// DOWNLOAD its own model via AssetInventory — the old SFSpeechRecognizer just
/// dies with "No Assistant asset" on a Mac that never enabled Dictation (ask us
/// how we know). Parakeet v3 still slots in behind this protocol later.
final class AppleTranscriber: Transcriber {
    private static let locale = Locale(identifier: "en-US")

    static func requestAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
    }

    /// Ensure the on-device model for our locale is installed, downloading if
    /// needed. Call once at startup; progress via the callback (nil = no
    /// download was needed).
    static func prepare(onProgress: @MainActor @escaping (Double) -> Void) async throws {
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [])
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else {
            throw SonoError.localeUnsupported
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            let progress = request.progress
            let poll = Task { @MainActor in
                while !Task.isCancelled {
                    onProgress(progress.fractionCompleted)
                    try? await Task.sleep(for: .milliseconds(300))
                }
            }
            defer { poll.cancel() }
            try await request.downloadAndInstall()
        }
    }

    func transcribe(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw SonoError.noAudio }

        let transcriber = SpeechTranscriber(locale: Self.locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        // Feed audio in the analyzer's preferred format.
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw SonoError.recognizerUnavailable
        }
        let buffer = try Self.buffer(from: samples, converting: format)

        // Collect finalized text while the analyzer runs.
        let collector = Task {
            var text = ""
            for try await result in transcriber.results where result.isFinal {
                text += String(result.text.characters)
            }
            return text
        }

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        continuation.yield(AnalyzerInput(buffer: buffer))
        continuation.finish()

        if let last = try await analyzer.analyzeSequence(stream) {
            try await analyzer.finalizeAndFinish(through: last)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        return try await collector.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Our 16 kHz mono floats -> a PCM buffer in `format`.
    private static func buffer(from samples: [Float], converting format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard let source = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: Recorder.sampleRate,
                                         channels: 1,
                                         interleaved: false),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: source,
                                              frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = inBuffer.floatChannelData
        else { throw SonoError.noAudio }
        inBuffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { channel[0].update(from: $0.baseAddress!, count: samples.count) }

        if format == source { return inBuffer }

        guard let converter = AVAudioConverter(from: source, to: format),
              let outBuffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(Double(samples.count) * format.sampleRate / source.sampleRate) + 1024)
        else { throw SonoError.noAudio }

        var consumed = false
        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, status in
            if consumed { status.pointee = .endOfStream; return nil }
            consumed = true
            status.pointee = .haveData
            return inBuffer
        }
        if let error { throw error }
        return outBuffer
    }
}
