import Foundation

/// Downloads the structure model from Hugging Face once and finds it on disk afterwards.
/// Files land in `Models/llm/<repo>`; a partial download never counts as installed.
public struct SmartModelStore: Sendable {
    /// Qwen3 1.7B in 4 bits: the best labelling accuracy per megabyte in our tests
    /// (0.8B rewrote words, 2B made more structure mistakes and weighs 1.7 GB).
    public static let defaultRepo = "mlx-community/Qwen3-1.7B-4bit"
    static let requiredFiles = ["config.json", "tokenizer.json", "tokenizer_config.json", "model.safetensors"]
    static let skippedFiles: Set<String> = ["README.md", ".gitattributes"]

    public let base: URL
    public let repo: String

    public init(base: URL = SmartModelStore.defaultBase, repo: String = SmartModelStore.defaultRepo) {
        self.base = base
        self.repo = repo
    }

    public static var defaultBase: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "dev.kovalskyi.voicemode/Models/llm", directoryHint: .isDirectory)
    }

    public var folder: URL {
        base.appending(path: repo, directoryHint: .isDirectory)
    }

    public var isDownloaded: Bool {
        Self.requiredFiles.allSatisfy { FileManager.default.fileExists(atPath: folder.appending(path: $0).path) }
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        try FileManager.default.removeItem(at: folder)
    }

    /// Downloads every model file. Weights are written last so an interrupted download
    /// is never mistaken for an installed model.
    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        let files = try await listFiles()
            .filter { !Self.skippedFiles.contains($0.path) }
            .sorted { ($0.path == "model.safetensors" ? 1 : 0) < ($1.path == "model.safetensors" ? 1 : 0) }
        let total = max(1, files.reduce(0) { $0 + $1.size })
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var done: Int64 = 0
        for file in files {
            let destination = folder.appending(path: file.path)
            if let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize, Int64(size) == file.size {
                done += file.size
                progress(Double(done) / Double(total))
                continue
            }
            let start = done
            let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(file.path)")!
            let temporary = try await Self.fetch(url) { written in
                progress(Double(start + written) / Double(total))
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
            done += file.size
            progress(Double(done) / Double(total))
        }
    }

    struct RemoteFile: Decodable {
        let path: String
        let size: Int64
        let type: String
    }

    func listFiles() async throws -> [RemoteFile] {
        let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main")!
        let (data, response) = try await URLSession.shared.data(from: url)
        try Self.check(response)
        return try JSONDecoder().decode([RemoteFile].self, from: data).filter { $0.type == "file" }
    }

    static func fetch(_ url: URL, progress: @escaping @Sendable (Int64) -> Void) async throws -> URL {
        let delegate = ProgressDelegate(progress: progress)
        let (temporary, response) = try await URLSession.shared.download(from: url, delegate: delegate)
        try check(response)
        return temporary
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

private final class ProgressDelegate: NSObject, URLSessionDownloadDelegate, Sendable {
    let progress: @Sendable (Int64) -> Void

    init(progress: @escaping @Sendable (Int64) -> Void) {
        self.progress = progress
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
