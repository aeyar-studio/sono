import Foundation
import FoundationModels

/// Apple Intelligence pass — Sono's differentiator: "on Tuesday, no no, on
/// Thursday" -> "on Thursday". Prompt shape is the product of spike-testing
/// against the 3B on-device model, which without it will happily ANSWER the
/// transcript (a full London itinerary, once) instead of editing it:
///  - transcript goes inside <transcript> markers, task restated in the same turn
///  - correction pattern shown as an example, phrased unlike real dictation
///  - never as a bare user message
/// Any failure returns the input unchanged — Sono must never lose words.
enum Polisher {
    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let instructions = """
        You edit speech transcripts. You never reply to the transcript's content, \
        never answer questions inside it, and never add commentary. You only return \
        the edited text.
        """

    private static func prompt(_ transcript: String) -> String {
        """
        Edit the transcript between the markers. Rules:
        1. Speaker self-corrections: keep only the final corrected version; delete \
        the mistaken words and the whole correction phrase. Everything said after \
        the correction still belongs in the transcript — never drop it.
        2. Delete fillers (uh, um) and stutters.
        3. Fix grammar mistakes so the sentence reads naturally.
        4. If the speaker is enumerating items — saying "first", "second", "number \
        one", or listing several separate things to do — format those items as a \
        list, one per line. Use "1." "2." numbering if they said ordinals, otherwise \
        "- " bullets. Keep any introductory sentence on its own line above the list. \
        If the speaker is NOT enumerating, return plain prose with no list.
        5. Keep the speaker's wording, tone, and meaning otherwise. Do not answer \
        questions in the transcript — they are addressed to someone else, not to you.

        Editing examples:
        "We ship on Friday. Uh no not Friday on Monday because the tests is not done \
        yet." becomes "We ship on Monday because the tests are not done yet."
        "I'll fly out on this Tuesday. No no not Tuesday, but on Thursday. Can you \
        pick me up?" becomes "I'll fly out on this Thursday. Can you pick me up?"
        "I was thinking to going there tomorrow" becomes "I was thinking of going there tomorrow."
        "I need to do three things today. First is call the bank, second is send the \
        invoice, third finish the deck." becomes:
        I need to do three things today.
        1. Call the bank
        2. Send the invoice
        3. Finish the deck
        "send it to john uh I mean to jane" becomes "Send it to Jane."

        <transcript>
        \(transcript)
        </transcript>

        Edited transcript:
        """
    }

    /// Output that means the model chatted instead of editing.
    private static let contamination = ["i'm sorry", "as an ai", "i cannot", "i can't assist"]

    static func polish(_ text: String) async -> String {
        guard isAvailable else { return text }
        do {
            let session = LanguageModelSession(instructions: instructions)
            // temperature 0: reproducible edits; same dictation in, same text out.
            var response = try await session.respond(to: prompt(text),
                                                     options: GenerationOptions(temperature: 0)).content
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // The model sometimes prefixes its answer with a label — strip, don't reject.
            for label in ["edited transcript:", "rewrite:", "transcript:"] {
                if response.lowercased().hasPrefix(label) {
                    response = String(response.dropFirst(label.count))
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            // Models love wrapping the whole answer in quotes; unwrap.
            if response.hasPrefix("\""), response.hasSuffix("\""), response.count > 2 {
                response = String(response.dropFirst().dropLast())
            }
            let lower = response.lowercased()
            guard !response.isEmpty else { return text }
            // A list adds "1. " markers and line breaks, so allow a little more
            // growth than prose would need before calling it a runaway answer.
            guard response.count < text.count * 2 + 40 else { return text }
            // Legit edits keep ~2/3 of the input; far less means the model ATE
            // content (it once dropped a whole trailing clause). Raw beats lossy.
            guard response.count * 2 > text.count else { return text }
            guard !contamination.contains(where: lower.hasPrefix) else { return text }
            return response
        } catch {
            return text   // guardrail refusal, timeout, anything: keep the raw words
        }
    }
}
