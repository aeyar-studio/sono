import Foundation
import HuggingFace
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

/// Local polish backend: Qwen3 4B, 4-bit, running through MLX.
///
/// Why this exists when Apple Intelligence is also on device:
///  - Apple Intelligence needs supported hardware and is not in every region.
///    This runs on any Apple Silicon Mac.
///  - Its context window is 4,096 tokens. Qwen3 has 32,768, so a long dictation
///    is not silently truncated.
///
/// Why 4B and not something smaller. 0.6B and 1.7B were both measured against a
/// self-correction set and both failed in the one direction that cannot ship:
/// asked to edit "book the table for six people. Sorry for eight people." they
/// deleted the correction and kept SIX. That is silently wrong, reads perfectly,
/// and no length or refusal guard can catch it. 0.6B also replaced one input
/// with a verbatim copy of a few-shot example. 4B resolves corrections correctly,
/// including two in one breath, and its only observed miss is under-editing,
/// which leaves the speaker's own words in place.
///
/// An actor because the weights are shared state and two dictations must never
/// enter the model at once.
actor LocalPolisher {
    static let shared = LocalPolisher()

    enum State: Equatable, Sendable {
        case idle
        /// Real bytes against a known total, so the UI can show a true percent.
        case downloading(received: Int64, total: Int64)
        case verifying(String)
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    private var container: ModelContainer?

    /// Loaded from our own copy on disk, not from the Hugging Face hub. The hub
    /// path works, but its progress reporting does not cover the weights file,
    /// so there was no honest percentage to show while 2 GB arrived.

    /// Qwen3 reasons out loud by default. That is seconds of latency plus a
    /// monologue to discard, so it is switched off. `/no_think` is the soft
    /// switch that works through any chat API; `PolishRules.stripThinking`
    /// catches the empty `<think></think>` block it emits anyway.
    private static let noThink = " /no_think"

    /// Enough to edit a spoken paragraph, and a bound on runaway generation.
    private static let maxTokens = 600

    /// Checked on disk rather than via a flag, so a partly removed model cannot
    /// claim to be ready.
    nonisolated static var isDownloaded: Bool { LocalModelDownloader.isPresent }

    /// What the first run costs, for the sentence shown before it starts.
    static let downloadBytes: Int64 = LocalModelDownloader.archiveBytes

    func currentState() -> State { state }

    func polish(_ text: String) async -> String {
        do {
            let container = try await ensureLoaded()
            // System turn, then the worked examples as real turns, then the
            // actual transcript. The model copies the demonstrated behaviour.
            var chat: [Chat.Message] = [.system(PolishRules.localSystem)]
            for shot in PolishRules.localShots {
                chat.append(.user(shot.said))
                chat.append(.assistant(shot.edited))
            }
            chat.append(.user(text + Self.noThink))
            let input = UserInput(chat: chat)
            let prepared = try await container.prepare(input: input)
            let stream = try await container.generate(
                input: prepared,
                parameters: GenerateParameters(maxTokens: Self.maxTokens,
                                               temperature: 0))   // greedy, reproducible
            var raw = ""
            for await item in stream {
                if case .chunk(let piece) = item { raw += piece }
            }
            return PolishRules.accept(raw, original: text) ?? text
        } catch {
            state = .failed(error.localizedDescription)
            return text   // download failure, out of memory, anything: keep the raw words
        }
    }

    /// Downloads the weights on first use, then keeps them resident. Reloading
    /// per dictation would add seconds to every paste.
    private func ensureLoaded() async throws -> ModelContainer {
        if let container { return container }

        state = .downloading(received: 0, total: LocalModelDownloader.archiveBytes)
        let directory = try await LocalModelDownloader.ensureModel(
            onProgress: { received, total in
                Task { await LocalPolisher.shared.note(received, total) }
            },
            onStage: { stage in
                Task { await LocalPolisher.shared.stage(stage) }
            })

        state = .loading
        // A plain directory: no hub, no network, nothing left to resolve.
        let loaded = try await #huggingFaceLoadModelContainer(
            configuration: ModelConfiguration(directory: directory))
        container = loaded
        state = .ready
        return loaded
    }

    private func note(_ received: Int64, _ total: Int64) {
        guard case .downloading = state else { return }
        state = .downloading(received: received, total: total)
    }

    private func stage(_ text: String) { state = .verifying(text) }

    /// Pull the weights when the engine is chosen, so the first dictation is not
    /// the one that waits on a 2.3 GB download.
    func prefetch() async {
        _ = try? await ensureLoaded()
    }
}
