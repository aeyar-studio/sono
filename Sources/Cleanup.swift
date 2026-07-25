import Foundation

/// Cheap text cleanup that needs no model. Only unambiguous non-words count as
/// fillers — "like", "so" and "well" carry meaning and are left alone.
///
/// Every pattern here operates on horizontal whitespace only. The polish layer
/// can return a multi-line list, and collapsing `\s+` would flatten it back into
/// one paragraph — which is exactly the bug this comment exists to prevent.
enum Cleanup {
    private static let fillers = ["uh", "um", "umm", "uhm", "uhh", "erm", "er", "ah", "eh", "mm", "hmm", "mhm"]

    static func strip(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(
            of: "\\b(?:\(fillers.joined(separator: "|")))\\b,?[ \\t]*",
            with: "",
            options: [.regularExpression, .caseInsensitive])

        // Stutters: "the the thing" -> "the thing". Same line only.
        s = s.replacingOccurrences(of: "\\b(\\w+)([ \\t]+\\1\\b)+",
                                   with: "$1",
                                   options: [.regularExpression, .caseInsensitive])

        // Tidy what the deletions left behind, without touching line breaks.
        s = s.replacingOccurrences(of: "[ \\t]+([,.!?;:])", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "[ \\t]+\n", with: "\n", options: .regularExpression)
        // Leading junk on the first line only; a list's "-" or "1." must survive.
        s = s.replacingOccurrences(of: "\\A[ \\t,.!?;:]+", with: "", options: .regularExpression)
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        return s.isEmpty ? text : capitalizeFirst(s)
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }

    #if DEBUG
    static func selfTest() {
        assert(strip("um so I uh went to the store") == "So I went to the store")
        assert(strip("the the thing") == "The thing")
        assert(strip("I like this plan") == "I like this plan", "real words are never fillers")
        assert(strip("um") == "um", "all-filler input keeps the original")

        // Lists from the polish layer must survive intact.
        let list = "Today I need to do two things.\n1. Call the bank\n2. Send the invoice"
        assert(strip(list) == list, "newlines and list markers must survive: \(strip(list))")
        let bullets = "Groceries:\n- milk\n- eggs"
        assert(strip(bullets) == bullets, "bullet markers must survive: \(strip(bullets))")
        assert(strip("Plan:\n- uh milk\n- eggs") == "Plan:\n- milk\n- eggs",
               "fillers still go, per line")
        print("Cleanup.selfTest ok")
    }
    #endif
}
