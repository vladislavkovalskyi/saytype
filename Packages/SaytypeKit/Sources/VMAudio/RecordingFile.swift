import Foundation
import VMCore

/// What is known about a recording when it starts, stored inside the file so a recording a
/// crash cut short can still become a history entry with its app and time.
public struct RecordingInfo: Equatable, Sendable {
    public var date: Date
    public var appName: String?
    public var bundleID: String?
    public var modeID: String?

    public init(date: Date, appName: String? = nil, bundleID: String? = nil, modeID: String? = nil) {
        self.date = date
        self.appName = appName
        self.bundleID = bundleID
        self.modeID = modeID
    }
}

/// The recording format: a Core Audio Format file with 16 kHz mono Float32, exactly the samples
/// Whisper got. The data chunk is the last one and is written with an unknown size (−1), which
/// the format defines as "to the end of the file": the file is valid at every moment while it
/// grows, and after a crash it holds everything written up to it.
///
/// Layout: file header (8 bytes), `desc` (12 + 32), `info` (12 + n), `data` (12 + 4 + samples).
/// Big-endian headers, little-endian samples.
public enum RecordingFile {
    public static let fileExtension = "caf"
    static let sampleRate = 16_000.0
    static let bytesPerFrame = 4

    enum ReadError: Error {
        case notARecording
    }

    /// Header bytes up to and including the data chunk's edit count; samples follow.
    static func header(info: RecordingInfo) -> Data {
        var data = Data()
        data.append(ascii: "caff")
        data.append(bigEndian: UInt16(1))
        data.append(bigEndian: UInt16(0))

        data.append(ascii: "desc")
        data.append(bigEndian: Int64(32))
        data.append(bigEndian: sampleRate.bitPattern)
        data.append(ascii: "lpcm")
        // kCAFLinearPCMFormatFlagIsFloat | kCAFLinearPCMFormatFlagIsLittleEndian
        data.append(bigEndian: UInt32(3))
        data.append(bigEndian: UInt32(bytesPerFrame))
        data.append(bigEndian: UInt32(1))
        data.append(bigEndian: UInt32(1))
        data.append(bigEndian: UInt32(32))

        let entries = infoEntries(info)
        var body = Data()
        body.append(bigEndian: UInt32(entries.count))
        for (key, value) in entries {
            body.append(Data(key.utf8) + [0])
            body.append(Data(value.utf8) + [0])
        }
        data.append(ascii: "info")
        data.append(bigEndian: Int64(body.count))
        data.append(body)

        data.append(ascii: "data")
        data.append(bigEndian: Int64(-1))
        // Edit count.
        data.append(bigEndian: UInt32(0))
        return data
    }

    private static func infoEntries(_ info: RecordingInfo) -> [(String, String)] {
        var entries = [("recorded date", ISO8601DateFormatter().string(from: info.date))]
        if let app = info.appName { entries.append(("saytype app", app)) }
        if let bundle = info.bundleID { entries.append(("saytype bundle id", bundle)) }
        if let mode = info.modeID { entries.append(("saytype mode", mode)) }
        return entries
    }

    /// Where the samples start and what the `info` chunk says, read from the file's chunks.
    static func layout(of url: URL) throws -> (dataOffset: UInt64, sizeOffset: UInt64, info: RecordingInfo?) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let head = try handle.read(upToCount: 8), head.count == 8, head.prefix(4) == Data("caff".utf8) else {
            throw ReadError.notARecording
        }
        var offset: UInt64 = 8
        var info: RecordingInfo?
        while true {
            try handle.seek(toOffset: offset)
            guard let chunk = try handle.read(upToCount: 12), chunk.count == 12 else { throw ReadError.notARecording }
            let type = String(decoding: chunk.prefix(4), as: UTF8.self)
            let size = Int64(bigEndian: chunk.dropFirst(4).withUnsafeBytes { $0.loadUnaligned(as: Int64.self) })
            if type == "data" {
                // Samples start after the edit count.
                return (offset + 12 + 4, offset + 4, info)
            }
            guard size >= 0 else { throw ReadError.notARecording }
            if type == "info", let body = try handle.read(upToCount: Int(size)) {
                info = parseInfo(body)
            }
            offset += 12 + UInt64(size)
        }
    }

    private static func parseInfo(_ body: Data) -> RecordingInfo? {
        let strings = body.dropFirst(4).split(separator: 0, omittingEmptySubsequences: false).map { String(decoding: $0, as: UTF8.self) }
        var values: [String: String] = [:]
        var index = 0
        while index + 1 < strings.count {
            values[strings[index]] = strings[index + 1]
            index += 2
        }
        guard let stamp = values["recorded date"], let date = ISO8601DateFormatter().date(from: stamp) else { return nil }
        return RecordingInfo(date: date, appName: values["saytype app"], bundleID: values["saytype bundle id"], modeID: values["saytype mode"])
    }

    /// The samples as they were written, bit for bit. A partial sample at the end of a file a
    /// crash cut short is left out.
    public static func samples(at url: URL) throws -> [Float] {
        let layout = try layout(of: url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard UInt64(data.count) >= layout.dataOffset else { return [] }
        let bytes = data.dropFirst(Int(layout.dataOffset))
        let count = bytes.count / bytesPerFrame
        return [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
            bytes.withUnsafeBytes { raw in
                for i in 0..<count {
                    buffer[i] = Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: i * bytesPerFrame, as: UInt32.self)))
                }
            }
            initialized = count
        }
    }

    public static func info(at url: URL) -> RecordingInfo? {
        (try? layout(of: url))?.info
    }

    /// Seconds of audio in the file.
    public static func duration(at url: URL) -> Double {
        guard let layout = try? layout(of: url),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? UInt64,
              size > layout.dataOffset
        else { return 0 }
        return Double((size - layout.dataOffset) / UInt64(bytesPerFrame)) / sampleRate
    }

    /// Writes the real size into the data chunk and trims a partial sample at the end, for a file
    /// whose writer never finished. The file was already readable; this makes every reader agree.
    public static func seal(_ url: URL) throws {
        let layout = try layout(of: url)
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        let frames = end > layout.dataOffset ? (end - layout.dataOffset) / UInt64(bytesPerFrame) : 0
        let length = layout.dataOffset + frames * UInt64(bytesPerFrame)
        if length != end { try handle.truncate(atOffset: length) }
        var size = Data()
        size.append(bigEndian: Int64(4 + frames * UInt64(bytesPerFrame)))
        try handle.seek(toOffset: layout.sizeOffset)
        // Already sealed: leave the file as it is.
        guard try handle.read(upToCount: 8) != size else { return }
        try handle.seek(toOffset: layout.sizeOffset)
        try handle.write(contentsOf: size)
    }
}

/// Writes a recording while it is being made. The microphone delivers chunks on the main actor;
/// the file is created and every chunk is written in order on a queue of its own, never on the
/// audio thread and never on the main thread. A failed write loses the rest of the recording,
/// never the dictation: the samples in memory still go to Whisper.
public final class RecordingWriter: @unchecked Sendable {
    public let id: UUID
    public let url: URL
    /// Chunks between two syncs to disk: about 3 s of the microphone's 0.1 s chunks. What the
    /// process wrote survives a crash anyway; this bounds what a power cut can take.
    static let syncEvery = 32
    private let queue = DispatchQueue(label: "dev.kovalskyi.saytype.recording", qos: .utility)
    /// Touched only on `queue`.
    private var handle: FileHandle?
    private var unsynced = 0

    public init(id: UUID, url: URL, info: RecordingInfo) {
        self.id = id
        self.url = url
        queue.async { [self] in
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard FileManager.default.createFile(atPath: url.path, contents: RecordingFile.header(info: info)) else { return }
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                self.handle = handle
            } catch {
                handle = nil
            }
        }
    }

    public func append(_ samples: [Float]) {
        guard !samples.isEmpty else { return }
        queue.async { [self] in
            guard let handle else { return }
            // Samples are little-endian in the file, as in memory on every Mac saytype runs on.
            let data = samples.withUnsafeBufferPointer { Data(buffer: $0) }
            do {
                try handle.write(contentsOf: data)
            } catch {
                // A full disk: stop here, the file keeps what it has.
                try? handle.close()
                self.handle = nil
                return
            }
            unsynced += 1
            if unsynced >= Self.syncEvery {
                unsynced = 0
                try? handle.synchronize()
            }
        }
    }

    /// Writes what is queued, seals the file and closes it.
    public func finish() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                if let handle {
                    try? handle.synchronize()
                    try? handle.close()
                    self.handle = nil
                    try? RecordingFile.seal(url)
                }
                done.resume()
            }
        }
    }

    /// Stops writing and deletes the file: the recording was cancelled.
    public func discard() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                try? handle?.close()
                handle = nil
                try? FileManager.default.removeItem(at: url)
                done.resume()
            }
        }
    }
}

private extension Data {
    mutating func append(ascii: String) {
        append(contentsOf: Array(ascii.utf8))
    }

    mutating func append<T: FixedWidthInteger>(bigEndian value: T) {
        Swift.withUnsafeBytes(of: value.bigEndian) { append(contentsOf: $0) }
    }
}
