import Foundation
import VMCore

/// The folder with the recordings of recent dictations. A recording's file is named after its
/// history record: `<record id>.caf`.
public struct RecordingArchive: Sendable {
    public let folder: URL

    public init(folder: URL = RecordingArchive.defaultFolder) {
        self.folder = folder
    }

    /// `~/Library/Application Support/dev.kovalskyi.saytype/Audio`, next to the history file.
    public static var defaultFolder: URL {
        HistoryStore.defaultURL.deletingLastPathComponent().appending(path: "Audio", directoryHint: .isDirectory)
    }

    public static func fileName(for id: UUID) -> String {
        "\(id.uuidString).\(RecordingFile.fileExtension)"
    }

    public func url(for fileName: String) -> URL {
        folder.appending(path: fileName)
    }

    /// Starts writing the recording for the record `id`. The file appears a moment later, on the
    /// writer's queue.
    public func start(id: UUID, info: RecordingInfo) -> RecordingWriter {
        RecordingWriter(id: id, url: url(for: Self.fileName(for: id)), info: info)
    }

    /// Names of the files in the folder.
    public func files() -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    /// Deletes every file of these recordings.
    public func delete(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for file in files() {
            guard let id = AudioKeeping.recordingID(file), ids.contains(id) else { continue }
            try? FileManager.default.removeItem(at: url(for: file))
        }
    }

    public func deleteAll() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Bytes on disk, for the settings readout.
    public func size() -> Int64 {
        files().reduce(0) { total, file in
            let size = (try? FileManager.default.attributesOfItem(atPath: url(for: file).path))?[.size] as? Int64
            return total + (size ?? 0)
        }
    }

    /// Recordings on disk that no record points to and that are not being written: what a crash
    /// or a forced quit left behind. Each one with audio in it is sealed and returned as a record
    /// that is not transcribed; the rest are empty or unreadable and come back as `junk`.
    public func recover(known records: [DictationRecord], active: Set<UUID> = []) -> (found: [DictationRecord], junk: Set<UUID>) {
        let files = files()
        // A crash after the record was saved leaves its file unsealed; readable, but sealed is tidier.
        for file in files where file.hasSuffix(".\(RecordingFile.fileExtension)") {
            guard let id = AudioKeeping.recordingID(file), !active.contains(id) else { continue }
            try? RecordingFile.seal(url(for: file))
        }
        let strays = AudioKeeping.strays(files: files, records: records, active: active)
        let known = Set(records.map(\.id))
        var found: [DictationRecord] = []
        var junk = Set<UUID>()
        for id in strays {
            let url = url(for: Self.fileName(for: id))
            // A record whose audio was unlinked, or a file that is not a recording: nothing to recover.
            guard !known.contains(id), FileManager.default.fileExists(atPath: url.path) else {
                junk.insert(id)
                continue
            }
            try? RecordingFile.seal(url)
            let duration = RecordingFile.duration(at: url)
            guard duration > 0 else {
                junk.insert(id)
                continue
            }
            let info = RecordingFile.info(at: url)
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
            found.append(DictationRecord(
                id: id,
                text: "",
                raw: "",
                appName: info?.appName,
                bundleID: info?.bundleID,
                duration: duration,
                date: info?.date ?? modified ?? Date(),
                audio: Self.fileName(for: id),
                modeID: info?.modeID,
                failure: .interrupted
            ))
        }
        return (found.sorted { $0.date > $1.date }, junk)
    }
}
