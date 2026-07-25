import Foundation
import CryptoKit

/// Fetches the speech model on first launch so a fresh install works with no
/// manual setup. Downloads the archive, extracts it into Application Support and
/// verifies the four files the recognizer needs.
///
/// ~465 MB compressed, ~640 MB on disk. Kept out of the app bundle deliberately:
/// it would otherwise make every app update a 640 MB download.
enum ModelDownloader {
    enum Stage {
        case checking
        case downloading(fraction: Double)
        case verifying
        case extracting
        case ready
    }

    enum Failure: LocalizedError {
        case noSpace(needed: Int64, free: Int64)
        case badArchive
        case incomplete
        case checksumMismatch

        var errorDescription: String? {
            switch self {
            case .noSpace(let needed, let free):
                let f = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                let n = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
                return "Needs \(n) free, only \(f) available"
            case .badArchive: return "The download could not be unpacked"
            case .incomplete: return "The download was missing files"
            case .checksumMismatch: return "The download was corrupted"
            }
        }
    }

    static let modelName = "sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"

    /// Our own mirror, so a third party retagging or deleting their release can't
    /// break every new install. Pinned by hash: this asset must never be replaced
    /// in place — publish a new tag and update both constants together.
    private static let archiveURL = URL(string:
        "https://github.com/aeyar-studio/sono-models/releases/download/model-v3-int8/sono-parakeet-v3-int8.tar.gz")!
    private static let archiveSHA256 =
        "3633e3b554ab6804142b7fa0e0fac6ede70caf400d4dd5a3bf056ad9500efe7d"
    /// Download + extracted, with headroom.
    private static let requiredBytes: Int64 = 1_250_000_000

    /// Same location History uses by default, resolved without touching the
    /// @MainActor type (this runs off the main actor).
    static var supportFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sono")
    }
    private static var modelsFolder: URL { supportFolder.appendingPathComponent("models") }

    /// Returns paths for the recognizer, downloading the model first if needed.
    /// Safe to call on every launch — it exits immediately once the model exists.
    static func ensureModel(onStage: @escaping @Sendable (Stage) -> Void) async throws
        -> ParakeetTranscriber.ModelPaths {
        onStage(.checking)
        if let existing = ParakeetTranscriber.ModelPaths.locate() {
            onStage(.ready)
            return existing
        }

        try checkSpace()

        let fm = FileManager.default
        try fm.createDirectory(at: modelsFolder, withIntermediateDirectories: true)
        let archive = modelsFolder.appendingPathComponent("\(modelName).tar.gz")
        try? fm.removeItem(at: archive)          // clear any half-finished attempt

        try await Download.run(from: archiveURL, to: archive) { fraction in
            onStage(.downloading(fraction: fraction))
        }

        onStage(.verifying)
        defer { try? fm.removeItem(at: archive) }
        guard try sha256(of: archive) == archiveSHA256 else {
            throw Failure.checksumMismatch
        }

        onStage(.extracting)
        try extract(archive, into: modelsFolder)

        guard let paths = ParakeetTranscriber.ModelPaths.locate() else { throw Failure.incomplete }
        onStage(.ready)
        return paths
    }

    private static func checkSpace() throws {
        let values = try? supportFolder.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
        guard free >= requiredBytes else {
            throw Failure.noSpace(needed: requiredBytes, free: free)
        }
    }

    /// Streamed SHA-256 — the archive is ~456 MB, so it is never held in memory.
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// bsdtar ships with macOS and auto-detects the compression, so the archive
    /// format can change without touching this.
    private static func extract(_ archive: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xf", archive.path, "-C", folder.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure.badArchive }
    }
}

/// URLSession download wrapped for async/await, with byte-level progress —
/// `URLSession.download(from:)` reports none, and a 465 MB download without a
/// progress figure looks like a hang.
private final class Download: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<Void, Error>?

    static func run(from url: URL,
                    to destination: URL,
                    onProgress: @escaping @Sendable (Double) -> Void) async throws {
        let downloader = Download(destination: destination, onProgress: onProgress)
        try await downloader.start(url: url)
    }

    private init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    private func start(url: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForResource = 3600   // large file, slow links
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite totalBytesExpected: Int64) {
        guard totalBytesExpected > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpected))
    }

    func urlSession(_ session: URLSession,
                    downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted the moment this returns, so move it here.
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else { return }        // success is handled above
        continuation?.resume(throwing: error)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}
