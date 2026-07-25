import Foundation
import CSherpaOnnx

/// NVIDIA Parakeet TDT 0.6b v3 via sherpa-onnx — the model this app was always
/// meant to run. Same stack as voiceflow, minus Node.
final class ParakeetTranscriber: Transcriber {
    private let recognizer: OpaquePointer

    /// Model files on disk, or nil if not downloaded yet.
    struct ModelPaths {
        let encoder, decoder, joiner, tokens: String

        static func locate() -> ModelPaths? {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Sono/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8")
            func find(_ suffix: String) -> String? {
                guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
                return names.first { $0.hasSuffix(suffix) }.map { dir.appendingPathComponent($0).path }
            }
            guard let encoder = find("encoder.int8.onnx") ?? find("encoder.onnx"),
                  let decoder = find("decoder.int8.onnx") ?? find("decoder.onnx"),
                  let joiner = find("joiner.int8.onnx") ?? find("joiner.onnx"),
                  let tokens = find("tokens.txt")
            else { return nil }
            return ModelPaths(encoder: encoder, decoder: decoder, joiner: joiner, tokens: tokens)
        }
    }

    /// Blocking for a few seconds while ONNX sessions build — call off-main.
    init?(paths: ModelPaths) {
        var config = SherpaOnnxOfflineRecognizerConfig()
        config.model_config.transducer.encoder = UnsafePointer(strdup(paths.encoder))
        config.model_config.transducer.decoder = UnsafePointer(strdup(paths.decoder))
        config.model_config.transducer.joiner = UnsafePointer(strdup(paths.joiner))
        config.model_config.tokens = UnsafePointer(strdup(paths.tokens))
        config.model_config.model_type = UnsafePointer(strdup("nemo_transducer"))
        config.model_config.provider = UnsafePointer(strdup("cpu"))
        config.model_config.num_threads = Int32(max(2, min(4, ProcessInfo.processInfo.activeProcessorCount - 1)))
        config.feat_config.sample_rate = 16000
        config.feat_config.feature_dim = 80
        config.decoding_method = UnsafePointer(strdup("greedy_search"))

        let created = SherpaOnnxCreateOfflineRecognizer(&config)
        free(UnsafeMutablePointer(mutating: config.model_config.transducer.encoder))
        free(UnsafeMutablePointer(mutating: config.model_config.transducer.decoder))
        free(UnsafeMutablePointer(mutating: config.model_config.transducer.joiner))
        free(UnsafeMutablePointer(mutating: config.model_config.tokens))
        free(UnsafeMutablePointer(mutating: config.model_config.model_type))
        free(UnsafeMutablePointer(mutating: config.model_config.provider))
        free(UnsafeMutablePointer(mutating: config.decoding_method))
        guard let created else { return nil }
        recognizer = created
    }

    deinit { SherpaOnnxDestroyOfflineRecognizer(recognizer) }

    // voiceflow's memory bound, ported: Parakeet's encoder is full self-attention,
    // so one long decode can OOM-abort the process. Decode in windows of at most
    // MAX_CHUNK samples, splitting at the quietest 30ms so we cut between words.
    private static let minChunk = 12 * 16000
    private static let maxChunk = 18 * 16000
    private static let scanWin = 480    // 30 ms
    private static let scanHop = 160    // 10 ms

    func transcribe(_ samples: [Float]) async throws -> String {
        guard !samples.isEmpty else { throw SonoError.noAudio }
        // ONNX decode is CPU-bound; keep it off the cooperative pool's main lanes.
        let recognizer = self.recognizer
        return try await Task.detached(priority: .userInitiated) {
            var parts: [String] = []
            var start = 0
            while start < samples.count {
                let end: Int
                if start + Self.maxChunk >= samples.count {
                    end = samples.count
                } else {
                    end = Self.quietestSplit(samples, lo: start + Self.minChunk, hi: start + Self.maxChunk)
                }
                parts.append(Self.decode(recognizer, Array(samples[start..<end])))
                start = end
            }
            let text = parts.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { throw SonoError.noAudio }
            return text
        }.value
    }

    private static func decode(_ recognizer: OpaquePointer, _ samples: [Float]) -> String {
        guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { return "" }
        defer { SherpaOnnxDestroyOfflineStream(stream) }
        samples.withUnsafeBufferPointer {
            SherpaOnnxAcceptWaveformOffline(stream, 16000, $0.baseAddress, Int32(samples.count))
        }
        SherpaOnnxDecodeOfflineStream(recognizer, stream)
        guard let result = SherpaOnnxGetOfflineStreamResult(stream) else { return "" }
        defer { SherpaOnnxDestroyOfflineRecognizerResult(result) }
        return result.pointee.text.map { String(cString: $0) } ?? ""
    }

    /// Quietest 30ms midpoint within [lo, hi] — a natural pause between words.
    private static func quietestSplit(_ samples: [Float], lo: Int, hi: Int) -> Int {
        let lo = max(0, lo)
        let hi = min(samples.count - scanWin, hi)
        var best = lo
        var bestEnergy = Float.infinity
        var i = lo
        while i <= hi {
            var energy: Float = 0
            for j in 0..<scanWin { energy += samples[i + j] * samples[i + j] }
            if energy < bestEnergy { bestEnergy = energy; best = i }
            i += scanHop
        }
        return best + scanWin / 2
    }
}
