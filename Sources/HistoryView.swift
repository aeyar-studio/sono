import SwiftUI
import AppKit

/// Dictation history. Grouped by day, each row anchored by its time, with the
/// metadata as chips and long transcripts clamped so the list stays scannable.
struct HistoryList: View {
    @ObservedObject private var history = History.shared
    @State private var justCopied: Date?
    @State private var expanded: Set<Date> = []

    /// Entries bucketed by calendar day, newest day first.
    private var groups: [(title: String, entries: [History.Entry])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: history.entries) { calendar.startOfDay(for: $0.ts) }
        return buckets.keys.sorted(by: >).map { day in
            (title: Self.dayTitle(day, calendar: calendar),
             entries: buckets[day]!.sorted { $0.ts > $1.ts })
        }
    }

    private static func dayTitle(_ day: Date, calendar: Calendar) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    var body: some View {
        ScrollView {
            if history.entries.isEmpty {
                EmptyHistory()
                    .padding(.horizontal, 26)
                    .padding(.vertical, 22)
            } else {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(group.title.uppercased())
                                .font(Type.font(9.5, .semibold))
                                .tracking(0.6)
                                .foregroundStyle(Palette.inkMuted)
                                .padding(.leading, 2)

                            VStack(spacing: 7) {
                                ForEach(group.entries) { entry in
                                    Row(entry: entry,
                                        copied: justCopied == entry.ts,
                                        expanded: expanded.contains(entry.ts),
                                        onToggleExpand: { toggleExpand(entry) },
                                        onCopy: { copy(entry) },
                                        onDelete: { history.delete(entry) })
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 26)
                .padding(.vertical, 22)
                .frame(maxWidth: 940, alignment: .leading)
            }
        }
        .background(Palette.canvas)
    }

    private func toggleExpand(_ entry: History.Entry) {
        if expanded.contains(entry.ts) { expanded.remove(entry.ts) } else { expanded.insert(entry.ts) }
    }

    private func copy(_ entry: History.Entry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        justCopied = entry.ts
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            if justCopied == entry.ts { justCopied = nil }
        }
    }

    // MARK: - Row

    private struct Row: View {
        @ObservedObject private var themeStore = ThemeStore.shared
        private var theme: Theme { themeStore.theme }
        let entry: History.Entry
        let copied: Bool
        let expanded: Bool
        let onToggleExpand: () -> Void
        let onCopy: () -> Void
        let onDelete: () -> Void
        @State private var hovering = false

        /// Long transcripts get clamped; only those offer the expand control.
        private var isLong: Bool { entry.text.count > 240 }

        var body: some View {
            HStack(alignment: .top, spacing: 0) {
                // Left rail: a violet stripe that appears on hover, so the row
                // being acted on is unmistakable without moving anything.
                RoundedRectangle(cornerRadius: 2)
                    .fill(hovering ? theme.accent : .clear)
                    .frame(width: 2.5)
                    .padding(.vertical, 14)

                VStack(alignment: .leading, spacing: 9) {
                    header
                    Text(entry.text)
                        .font(Type.font(13))
                        .lineSpacing(4)
                        .foregroundStyle(Palette.ink)
                        .textSelection(.enabled)
                        .lineLimit(expanded ? nil : 4)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 720, alignment: .leading)

                    if isLong {
                        Button(action: onToggleExpand) {
                            Text(expanded ? "Show less" : "Show more")
                                .font(Type.font(10.5, .medium))
                                .foregroundStyle(theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, 14)
                .padding(.vertical, 14)
            }
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hovering ? Palette.sidebar : Palette.canvas))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(hovering ? Palette.border : Palette.borderSoft))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var header: some View {
            HStack(spacing: 7) {
                Text(entry.ts.formatted(date: .omitted, time: .shortened))
                    .font(Type.font(11.5, .semibold))
                    .foregroundStyle(Palette.inkSecondary)
                    .monospacedDigit()

                Chip(text: Metrics.shortDuration(entry.duration))
                Chip(text: "\(Metrics.wordCount(entry.text)) words")
                if !entry.pasted {
                    Chip(text: "copied only", tint: Palette.warning, fill: Palette.warningWash)
                }

                Spacer(minLength: 8)

                HStack(spacing: 2) {
                    IconButton(symbol: copied ? "checkmark" : "doc.on.doc",
                               tint: copied ? theme.accent : Palette.inkSecondary,
                               help: copied ? "Copied" : "Copy text",
                               action: onCopy)
                    IconButton(symbol: "trash",
                               tint: Palette.inkSecondary,
                               help: "Delete",
                               action: onDelete)
                }
                .opacity(hovering || copied ? 1 : 0)
            }
        }
    }

    private struct Chip: View {
        let text: String
        var tint: Color = Palette.inkSecondary
        var fill: Color = Palette.borderSoft

        var body: some View {
            Text(text)
                .font(Type.font(10, .medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 6.5)
                .padding(.vertical, 2.5)
                .background(RoundedRectangle(cornerRadius: 5).fill(fill))
        }
    }

    private struct IconButton: View {
        let symbol: String
        let tint: Color
        let help: String
        let action: () -> Void
        @State private var hovering = false

        var body: some View {
            Button(action: action) {
                Image(systemName: symbol)
                    .font(Type.font(11, .medium))
                    .foregroundStyle(tint)
                    .frame(width: 25, height: 25)
                    .background(RoundedRectangle(cornerRadius: 6.5)
                        .fill(hovering ? Palette.border.opacity(0.8) : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(help)
        }
    }

    private struct EmptyHistory: View {
        var body: some View {
            Panel(padding: 34) {
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "clock")
                        .font(Type.font(18))
                        .foregroundStyle(Palette.inkMuted)
                    Text("Nothing here yet")
                        .font(Type.font(15, .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Dictations you make will be listed here, with a copy button for each.")
                        .font(Type.font(12))
                        .foregroundStyle(Palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 380, alignment: .leading)
            }
        }
    }
}
