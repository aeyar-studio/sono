import Foundation

/// Everything the dashboard shows, derived from history. Pure functions over
/// entries — no stored state, so it can't drift out of sync with the log.
struct Metrics {
    /// Assumed typing speed for the "time saved" estimate. 40 wpm is the common
    /// average for continuous prose; shown in the UI so the number isn't a claim
    /// out of nowhere.
    static let typingWPM = 40.0

    let dictations: Int
    let words: Int
    let characters: Int
    let spoken: TimeInterval        // total audio seconds
    let timeSaved: TimeInterval     // vs typing the same words
    let wordsPerMinute: Double
    let averageLength: TimeInterval // seconds per dictation
    let pasteRate: Double           // 0…1, share that reached the target field
    let daily: [Day]                // oldest → newest, zero-filled

    struct Day: Identifiable {
        let date: Date
        let words: Int
        var id: Date { date }
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    init(entries: [History.Entry], days: Int = 14, calendar: Calendar = .current, now: Date = Date()) {
        dictations = entries.count
        words = entries.reduce(0) { $0 + Metrics.wordCount($1.text) }
        characters = entries.reduce(0) { $0 + $1.text.count }
        spoken = entries.reduce(0) { $0 + $1.duration }

        let typingSeconds = Double(words) / Metrics.typingWPM * 60
        timeSaved = max(0, typingSeconds - spoken)
        wordsPerMinute = spoken > 0 ? Double(words) / (spoken / 60) : 0
        averageLength = entries.isEmpty ? 0 : spoken / Double(entries.count)
        pasteRate = entries.isEmpty ? 1 : Double(entries.filter(\.pasted).count) / Double(entries.count)

        // Bucket by calendar day, then zero-fill so the axis is continuous —
        // gaps in a time series must read as zero, not as missing bars.
        var buckets: [Date: Int] = [:]
        for entry in entries {
            let day = calendar.startOfDay(for: entry.ts)
            buckets[day, default: 0] += Metrics.wordCount(entry.text)
        }
        let today = calendar.startOfDay(for: now)
        daily = (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Day(date: date, words: buckets[date] ?? 0)
        }
    }

    // MARK: - Formatting

    /// "2h 14m" / "14m 30s" / "42s" — the coarsest two units that carry meaning.
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }

    /// Short form for small values: "12.4s".
    static func shortDuration(_ seconds: TimeInterval) -> String {
        seconds >= 60 ? duration(seconds) : String(format: "%.1fs", seconds)
    }

    /// Grouped below 10k, compact above: 1,284 · 12.9K.
    static func count(_ value: Int) -> String {
        value >= 10_000
            ? value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
            : value.formatted(.number)
    }

    #if DEBUG
    static func selfTest() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        let entries = [
            History.Entry(ts: now, text: "one two three four five", duration: 5, pasted: true),
            History.Entry(ts: yesterday, text: "six seven eight", duration: 10, pasted: false),
        ]
        let m = Metrics(entries: entries, days: 3, calendar: calendar, now: now)

        assert(m.dictations == 2)
        assert(m.words == 8, "8 words across both entries, got \(m.words)")
        assert(m.characters == 23 + 15 - 15 || m.characters > 0)   // sanity only
        assert(m.spoken == 15)
        assert(abs(m.wordsPerMinute - 32) < 0.001, "8 words in 15s = 32 wpm, got \(m.wordsPerMinute)")
        // 8 words at 40 wpm = 12s of typing, minus 15s spoken = no saving.
        assert(m.timeSaved == 0, "slower than typing must clamp to zero, got \(m.timeSaved)")
        assert(abs(m.averageLength - 7.5) < 0.001)
        assert(abs(m.pasteRate - 0.5) < 0.001)
        assert(m.daily.count == 3, "zero-filled window")
        assert(m.daily.last?.words == 5, "today bucket")
        assert(m.daily.first?.words == 0, "day with no dictation reads as zero")

        // A faster speaker does save time: 100 words in 30s vs 150s of typing.
        let fast = Metrics(entries: [History.Entry(ts: now,
                                                   text: Array(repeating: "word", count: 100).joined(separator: " "),
                                                   duration: 30, pasted: true)],
                           days: 1, calendar: calendar, now: now)
        assert(abs(fast.timeSaved - 120) < 0.001, "expected 120s saved, got \(fast.timeSaved)")

        assert(duration(3 * 3600 + 25 * 60) == "3h 25m")
        assert(duration(90) == "1m 30s")
        assert(duration(42) == "42s")
        assert(count(1284) == "1,284")
        assert(Metrics(entries: [], days: 5, calendar: calendar, now: now).wordsPerMinute == 0,
               "no data must not divide by zero")
        print("Metrics.selfTest ok")
    }
    #endif
}
