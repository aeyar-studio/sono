import Foundation
import AppKit

/// Dictation history — one JSON object per line, appended after each paste.
///
/// The file's folder is configurable so it can live in iCloud Drive (or Dropbox,
/// or anywhere synced): Apple does the syncing, Sono just writes a file. That's
/// why the format matters — append-only JSONL keyed by timestamp means merging
/// two Macs is a set union, with no conflict resolution to get wrong.
@MainActor
final class History: ObservableObject {
    static let shared = History()

    struct Entry: Codable, Identifiable, Equatable {
        let ts: Date
        let text: String
        let duration: Double     // seconds of audio
        let pasted: Bool         // false = only copied to clipboard
        var id: Date { ts }
    }

    @Published private(set) var entries: [Entry] = []

    // MARK: - Location

    static var defaultFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sono")
    }

    /// Where history is kept. A custom folder is how syncing works.
    static var folder: URL {
        guard let path = UserDefaults.standard.string(forKey: Settings.historyFolderKey),
              !path.isEmpty else { return defaultFolder }
        return URL(fileURLWithPath: path)
    }

    static var file: URL { folder.appendingPathComponent("history.jsonl") }

    static var isSynced: Bool {
        folder.path.contains("Mobile Documents") || folder.path.contains("Dropbox")
    }

    /// iCloud Drive's local folder, if the user has iCloud Drive switched on.
    static var iCloudDriveFolder: URL? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private init() {
        entries = Self.load()
        // Another Mac may have written to a synced folder while we were away.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in self.reload() }
        }
    }

    // MARK: - Mutation

    func add(text: String, duration: Double, pasted: Bool) {
        let entry = Entry(ts: Date(), text: text, duration: duration, pasted: pasted)
        // Union with whatever is on disk first, so a second Mac's entries are not
        // clobbered by this append.
        entries = Self.merge(Self.load(), entries + [entry])
        if entries.count > 550 { entries = Array(entries.prefix(450)) }
        write(entries)
    }

    /// Deletions are authoritative — merging the disk back in would resurrect them.
    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        write(entries)
    }

    func clear() {
        entries.removeAll()
        try? FileManager.default.removeItem(at: Self.file)
    }

    func reload() {
        let disk = Self.load()
        let merged = Self.merge(disk, entries)
        if merged != entries { entries = merged }
    }

    /// Point history at a new folder, carrying entries across and folding in
    /// anything already there (the case that matters: a folder another Mac synced).
    func move(to newFolder: URL) {
        let oldFile = Self.file
        UserDefaults.standard.set(newFolder.path, forKey: Settings.historyFolderKey)

        let combined = Self.merge(Self.load(), entries)   // load() now reads the new folder
        entries = combined
        write(combined)

        if oldFile != Self.file {
            try? FileManager.default.removeItem(at: oldFile)
        }
    }

    func resetLocation() {
        move(to: Self.defaultFolder)
    }

    // MARK: - Disk

    /// Newest first, de-duplicated by timestamp.
    private static func merge(_ a: [Entry], _ b: [Entry]) -> [Entry] {
        var byTimestamp: [Date: Entry] = [:]
        for entry in a + b { byTimestamp[entry.ts] = entry }
        return byTimestamp.values.sorted { $0.ts > $1.ts }
    }

    private static func load() -> [Entry] {
        guard let data = try? Data(contentsOf: file),
              let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return text.split(separator: "\n")
            .compactMap { $0.data(using: .utf8).flatMap { try? decoder.decode(Entry.self, from: $0) } }
            .sorted { $0.ts > $1.ts }
    }

    private func write(_ entries: [Entry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        let lines = entries.reversed().compactMap { entry -> String? in
            (try? encoder.encode(entry)).flatMap { String(data: $0, encoding: .utf8) }
        }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        try? (lines.joined(separator: "\n") + "\n").write(to: Self.file, atomically: true, encoding: .utf8)
    }
}
