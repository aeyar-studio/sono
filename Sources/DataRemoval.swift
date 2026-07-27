import Foundation
import AppKit

/// Wipes everything Sono has written outside its own bundle.
///
/// This exists because dragging a Mac app to the Trash removes only the .app —
/// the 640 MB speech model and the full transcript history would survive. For an
/// app that promises the text stays on your machine, leaving that behind after an
/// uninstall is the wrong default.
@MainActor
enum DataRemoval {
    /// What would be deleted, so the confirmation can be specific rather than vague.
    struct Inventory {
        let modelBytes: Int64
        /// The local enhancement model, when it has been downloaded.
        let llmBytes: Int64
        let historyBytes: Int64
        let historyPath: String
        let hasPreferences: Bool

        var totalBytes: Int64 { modelBytes + llmBytes + historyBytes }
        var readableTotal: String {
            ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
        }
        var readableModel: String {
            ByteCountFormatter.string(fromByteCount: modelBytes, countStyle: .file)
        }
        var readableLLM: String {
            ByteCountFormatter.string(fromByteCount: llmBytes, countStyle: .file)
        }
    }

    static var modelsFolder: URL {
        History.defaultFolder.appendingPathComponent("models")
    }

    /// Where MLX puts the local enhancement model.
    ///
    /// Not under Application Support: the Hugging Face hub cache is a SHARED
    /// directory, and anything else on this Mac that pulls a model uses it too.
    /// So only Sono's own repo folder is ever touched, never the cache itself.
    /// Deleting `~/.cache/huggingface` wholesale would take other tools' models
    /// with it.
    static var llmFolder: URL? {
        let repo = "mlx-community/Qwen3-4B-4bit"
        let slug = "models--" + repo.replacingOccurrences(of: "/", with: "--")
        let hub = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let dir = hub.appendingPathComponent(slug)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    static func inventory() -> Inventory {
        Inventory(modelBytes: size(of: modelsFolder),
                  llmBytes: llmFolder.map(size(of:)) ?? 0,
                  historyBytes: size(of: History.file),
                  historyPath: History.file.path,
                  hasPreferences: UserDefaults.standard.persistentDomain(forName: bundleID) != nil)
    }

    /// Delete the model, the history file (wherever it lives), the app-support
    /// folder and the preferences, then quit. The .app itself is the user's to
    /// drag to the Trash — we cannot remove the running bundle.
    static func removeEverythingAndQuit() {
        let fm = FileManager.default
        try? fm.removeItem(at: History.file)          // may be in iCloud Drive
        try? fm.removeItem(at: History.defaultFolder) // speech model + anything left

        // The local enhancement model, and only it. The lock file sits beside
        // the repo folder and is orphaned once the weights are gone.
        if let llm = llmFolder {
            try? fm.removeItem(at: llm)
            let locks = llm.deletingLastPathComponent()
                .appendingPathComponent(".locks")
                .appendingPathComponent(llm.lastPathComponent)
            try? fm.removeItem(at: locks)
        }

        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        UserDefaults.standard.synchronize()

        // Temp chimes are regenerated per launch; tidy them anyway.
        for name in ["sono-start", "sono-stop"] {
            try? fm.removeItem(at: fm.temporaryDirectory.appendingPathComponent("\(name).wav"))
        }

        NSApplication.shared.terminate(nil)
    }

    private static var bundleID: String {
        Bundle.main.bundleIdentifier ?? "com.aeyar.Sono"
    }

    private static func size(of url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }

        if !isDirectory.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
        guard let walker = fm.enumerator(at: url,
                                         includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey])
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}
