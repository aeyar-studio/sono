import Foundation
import FoundationModels

/// Apple Intelligence backend. Prompt shape is the product of spike-testing
/// against the 3B on-device model, which without it will happily ANSWER the
/// transcript (a full London itinerary, once) instead of editing it:
///  - transcript goes inside <transcript> markers, task restated in the same turn
///  - correction pattern shown as an example, phrased unlike real dictation
///  - never as a bare user message
///
/// The prompt and the acceptance rules now live in `PolishRules`, shared with the
/// local backend. Any failure returns the input unchanged: Sono must never lose words.
enum Polisher {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    static func polish(_ text: String) async -> String {
        guard isAvailable else { return text }
        do {
            let session = LanguageModelSession(instructions: PolishRules.instructions)
            // temperature 0: reproducible edits; same dictation in, same text out.
            let raw = try await session.respond(to: PolishRules.prompt(text),
                                                options: GenerationOptions(temperature: 0)).content
            return PolishRules.accept(raw, original: text) ?? text
        } catch {
            return text   // guardrail refusal, timeout, anything: keep the raw words
        }
    }
}
