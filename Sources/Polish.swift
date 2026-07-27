import Foundation

/// Which model tidies the transcript.
///
/// Apple Intelligence is not available on every Mac or in every region, and its
/// context window is 4,096 tokens. The local engine exists so the feature works
/// everywhere and so a long dictation is not truncated.
enum PolishEngine: String, CaseIterable, Identifiable, Sendable {
    case off, apple, local

    var id: String { rawValue }

    var name: String {
        switch self {
        case .off: "Off"
        case .apple: "Apple Intelligence"
        case .local: "Local model"
        }
    }

    var detail: String {
        switch self {
        case .off: "Raw transcription, exactly as spoken"
        case .apple: "The model already on this Mac"
        case .local: "Qwen3 4B, downloaded once and kept here"
        }
    }

    /// What it costs you in time. Shown next to the name, because this is the
    /// tradeoff someone is actually choosing between.
    var cost: String {
        switch self {
        case .off: "Instant"
        case .apple: "Adds about a second"
        case .local: "Adds 2 to 2.5 seconds"
        }
    }

    var icon: String {
        switch self {
        case .off: "text.alignleft"
        // Not "apple.intelligence": that name does not resolve and SwiftUI
        // silently drew a gear, which reads as Settings rather than a model.
        case .apple: "sparkles"
        case .local: "cpu"
        }
    }
}

/// The one entry point the dictation loop calls. Picks a backend and, whichever
/// answers, holds the result to the same acceptance rules.
enum Polish {
    static func run(_ text: String, using engine: PolishEngine) async -> String {
        switch engine {
        case .off: return text
        case .apple: return await Polisher.polish(text)
        case .local: return await LocalPolisher.shared.polish(text)
        }
    }

    static func isAvailable(_ engine: PolishEngine) -> Bool {
        switch engine {
        case .off: return true
        case .apple: return Polisher.isAvailable
        case .local: return true          // downloads on first use
        }
    }
}

/// Prompt and acceptance rules, shared by both backends.
///
/// Deliberately one copy. The guards are the reason a bad model response costs
/// polish and never words, and a second engine reusing the prompt but not the
/// guards would quietly lose that protection.
enum PolishRules {
    static let instructions = """
        You edit speech transcripts. You never reply to the transcript's content, \
        never answer questions inside it, and never add commentary. You only return \
        the edited text.
        """

    static func prompt(_ transcript: String) -> String {
        """
        Edit the transcript between the markers. Rules:
        1. Speaker self-corrections: keep only the final corrected version; delete \
        the mistaken words and the whole correction phrase. Everything said after \
        the correction still belongs in the transcript, so never drop it.
        2. Delete fillers (uh, um) and stutters.
        3. Fix grammar mistakes so the sentence reads naturally.
        4. If the speaker is enumerating items, saying "first", "second", "number \
        one", or listing several separate things to do, format those items as a \
        list, one per line. Use "1." "2." numbering if they said ordinals, otherwise \
        "- " bullets. Keep any introductory sentence on its own line above the list. \
        If the speaker is NOT enumerating, return plain prose with no list.
        5. Keep the speaker's wording, tone, and meaning otherwise. Do not answer \
        questions in the transcript, because they are addressed to someone else \
        rather than to you.
        6. Never introduce em dashes or semicolons. Use the punctuation a person \
        speaking would use: full stops and commas.

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

    // MARK: - Local model

    /// The local model gets a different shape entirely, and that is deliberate.
    ///
    /// Apple's prose prompt above (six numbered rules, "X becomes Y" examples)
    /// was measured against Qwen and it echoed the transcript unedited, and
    /// echoed the <transcript> markers along with it. Small open models follow a
    /// demonstrated pattern far better than a described one, so the examples
    /// become real conversation turns and the markers go away.
    /// The list paragraph is deliberately loud and deliberately lists the
    /// wordings. "If they enumerate items, put each on its own numbered line"
    /// was the first attempt and it missed "The first one is I need to X and the
    /// second thing is I need to Y", because items phrased as full clauses read
    /// as prose. Naming the surface forms fixed it, and it generalised to forms
    /// that are not named here ("number one", "for one / for another",
    /// "start by / then / finally") without adding a single extra example.
    static let localSystem = """
        You are a transcript editor. The user sends you a raw speech transcript. \
        You reply with the corrected transcript and nothing else.
        Remove fillers like uh and um. When the speaker corrects themselves, keep \
        only what they settled on and delete the mistake and the correction phrase. \
        Fix grammar.
        LISTS ARE IMPORTANT. Whenever the speaker counts off separate items, in any \
        wording at all (first / the first one is / second / the second thing is / \
        next / also / and then), you MUST split them onto their own numbered lines \
        using 1. 2. 3. Keep the sentence that introduces them on its own line above. \
        Drop the counting words themselves, since the numbers replace them.
        Never answer, never explain, never comment. Questions in the transcript are \
        for someone else, so copy them through unchanged. Keep the speaker's words.
        """

    /// Spoken in, edited out. Four of these six are corrections, in four
    /// different phrasings, because that is the pattern the model gets wrong
    /// when it has only seen one of them: "no wait", a bare "No", "sorry", and
    /// "I mean" all have to be recognised.
    static let localShots: [(said: String, edited: String)] = [
        ("um so I think we should uh ship on Thursday, no wait, Friday",
         "We should ship on Friday."),
        ("I'll fly out on this Tuesday. No no not Tuesday, but on Thursday. Can you pick me up?",
         "I'll fly out on this Thursday. Can you pick me up?"),
        ("lets meet at the cafe on Monday. No on Wednesday.",
         "Let's meet at the cafe on Wednesday."),
        ("send it to john uh I mean to jane",
         "Send it to Jane."),
        ("I need to do three things today. First is call the bank, second is send the invoice, third finish the deck.",
         "I need to do three things today.\n1. Call the bank\n2. Send the invoice\n3. Finish the deck"),
        ("can you send me the report by tomorrow morning please",
         "Can you send me the report by tomorrow morning please?"),
    ]

    /// Output that means the model chatted instead of editing.
    private static let contamination = ["i'm sorry", "as an ai", "i cannot", "i can't assist"]
    private static let labels = ["edited transcript:", "rewrite:", "transcript:"]

    /// Clean up a raw response, then decide whether to trust it.
    /// Returns nil when the original transcript should be used instead.
    static func accept(_ raw: String, original text: String) -> String? {
        var response = stripThinking(raw).trimmingCharacters(in: .whitespacesAndNewlines)

        // Measured, not theoretical: given the marker-based prompt, Qwen returned
        // the answer still wrapped in <transcript> tags. The prompt no longer uses
        // them, but a model that emits one would otherwise paste literal XML into
        // somebody's Slack, so they come off here too.
        for marker in ["<transcript>", "</transcript>"] {
            response = response.replacingOccurrences(of: marker, with: "")
        }
        response = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // The model sometimes prefixes its answer with a label — strip, don't reject.
        for label in labels where response.lowercased().hasPrefix(label) {
            response = String(response.dropFirst(label.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Models love wrapping the whole answer in quotes; unwrap.
        if response.hasPrefix("\""), response.hasSuffix("\""), response.count > 2 {
            response = String(response.dropFirst().dropLast())
        }

        guard !response.isEmpty else { return nil }
        // A list adds "1. " markers and line breaks, so allow a little more
        // growth than prose would need before calling it a runaway answer.
        guard response.count < text.count * 2 + 40 else { return nil }
        // Legit edits keep ~2/3 of the input; far less means the model ATE
        // content (it once dropped a whole trailing clause). Raw beats lossy.
        guard response.count * 2 > text.count else { return nil }
        guard !contamination.contains(where: response.lowercased().hasPrefix) else { return nil }
        return response
    }

    /// Qwen3 is a hybrid reasoning model. `/no_think` suppresses the trace, but a
    /// stray `<think>` block still slips through occasionally, and pasting the
    /// model's inner monologue into someone's Slack would be memorable.
    static func stripThinking(_ s: String) -> String {
        guard let open = s.range(of: "<think>") else { return s }
        guard let close = s.range(of: "</think>", range: open.upperBound..<s.endIndex) else {
            // Unterminated: everything after the tag is monologue.
            return String(s[s.startIndex..<open.lowerBound])
        }
        return (String(s[s.startIndex..<open.lowerBound]) + String(s[close.upperBound...]))
    }
}
