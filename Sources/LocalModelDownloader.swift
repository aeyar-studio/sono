import Foundation
import CryptoKit

/// Fetches the local enhancement model from our own R2 bucket.
///
/// Why not let MLX pull it from Hugging Face, which it does perfectly well:
/// the Progress object that path hands back does not track the large weights
/// file. Measured on a cold download, roughly 800 MB of 2.3 GB had arrived while
/// `fractionCompleted` was still under 0.01, so there was no honest number to
/// show and a user watching a frozen bar for twenty minutes reasonably concluded
/// it had hung. Twice.
///
/// Here the total is known before the first byte moves, so the percentage is
/// arithmetic rather than a library's estimate.
///
/// Hosted as a GitHub release asset next to the speech model, for the same
/// reasons: no bandwidth limit, no cost, and one place to look for both models.
/// It is 1.91 GiB against GitHub's 2 GiB per-asset ceiling, so a materially
/// larger model would need splitting or a different host.
enum LocalModelDownloader {
    /// Folder name inside Application Support/Sono/models.
    static let modelName = "sono-qwen3-4b-4bit"

    /// Our own mirror, pinned by hash, so a third party retagging or deleting
    /// their release cannot break every new install.
    private static let archiveURL = URL(string:
        "https://github.com/aeyar-studio/sono-models/releases/download/qwen3-4b-4bit/sono-qwen3-4b-4bit.tar.gz")!
    /// Bytes of the reassembled archive. Known up front, which is the entire
    /// point: percentage = received / this.
    static let archiveBytes: Int64 = 2_052_346_426
    private static let archiveSHA256 =
        "7bd8ccc42d7af798cca53cc46dc8ec61dcc9d7f5f72d1a41fa9318dcc08dcf3c"
    /// Archive plus extracted, with headroom.
    private static let requiredBytes: Int64 = 5_000_000_000

    enum Failure: LocalizedError {
        case noSpace(needed: Int64, free: Int64)
        case badArchive
        case checksumMismatch
        case incomplete

        var errorDescription: String? {
            switch self {
            case .noSpace(let needed, let free):
                let f = ByteCountFormatter.string(fromByteCount: free, countStyle: .file)
                let n = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
                return "Needs \(n) free, only \(f) available"
            case .badArchive: return "The download could not be unpacked"
            case .checksumMismatch: return "The download was corrupted"
            case .incomplete: return "The download was missing files"
            }
        }
    }

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sono/models/\(modelName)")
    }

    /// Present and usable. Checked by file rather than a UserDefaults flag, so a
    /// half-deleted model cannot report itself as ready.
    static var isPresent: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: folder.appendingPathComponent("config.json").path)
            && fm.fileExists(atPath: folder.appendingPathComponent("model.safetensors").path)
    }

    /// Downloads and unpacks, reporting bytes received against a known total.
    /// Returns the directory to hand to `ModelConfiguration(directory:)`.
    static func ensureModel(
        onProgress: @escaping @Sendable (Int64, Int64) -> Void,
        onStage: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        if isPresent { return folder }

        try checkSpace()

        let fm = FileManager.default
        let models = folder.deletingLastPathComponent()
        try fm.createDirectory(at: models, withIntermediateDirectories: true)
        let archive = models.appendingPathComponent("\(modelName).tar.gz")
        try? fm.removeItem(at: archive)      // clear any half-finished attempt

        try await PartDownload.run(from: archiveURL, to: archive) { received, total in
            // total from the server when it sends Content-Length, our constant
            // otherwise, so the percentage is right even on a truncated header.
            onProgress(received, total > 0 ? total : archiveBytes)
        }

        onStage("Verifying")
        guard try sha256(of: archive) == archiveSHA256 else {
            try? fm.removeItem(at: archive)
            throw Failure.checksumMismatch
        }

        onStage("Unpacking")
        try extract(archive, into: models)
        try? fm.removeItem(at: archive)

        guard isPresent else { throw Failure.incomplete }
        return folder
    }

    private static func checkSpace() throws {
        let values = try? folder.deletingLastPathComponent()
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        let free = values?.volumeAvailableCapacityForImportantUsage ?? Int64.max
        guard free >= requiredBytes else {
            throw Failure.noSpace(needed: requiredBytes, free: free)
        }
    }

    /// Streamed, so a 2 GB archive is never resident.
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

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

/// Downloads to `destination`, reporting bytes written against the expected total.
///
/// The same shape as the speech model's downloader, and for the same reasons:
/// `URLSession.download(from:)` reports no progress at all, and
/// `URLSession.bytes` yields one byte at a time, which is hopeless across 2 GB.
private final class PartDownload: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var continuation: CheckedContinuation<Void, Error>?

    static func run(from url: URL,
                    to destination: URL,
                    onProgress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        try await PartDownload(destination: destination, onProgress: onProgress).start(url: url)
    }

    private init(destination: URL, onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    private func start(url: URL) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            self.continuation = c
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForResource = 7200   // 2 GB on a slow link
            URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
                .downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // The temp file is deleted the moment this returns, so move it now.
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

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        guard let error else { return }          // success handled above
        continuation?.resume(throwing: error)
        continuation = nil
        session.finishTasksAndInvalidate()
    }
}
