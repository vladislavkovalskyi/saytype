@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import VMAudio
import VMCore

@Suite struct RecordingFileTests {
    func tempArchive() -> RecordingArchive {
        RecordingArchive(folder: FileManager.default.temporaryDirectory.appending(path: "saytype-audio-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    /// Speech-like samples with the quiet values a 16-bit file would round away.
    func samples(_ count: Int, seed: UInt64 = 1) -> [Float] {
        var state = seed
        return (0..<count).map { i in
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let noise = Float(Int64(bitPattern: state >> 11) % 1_000_000) / 1e11
            return 0.3 * sin(Float(i) * 0.05) * sin(Float(i) * 0.0007) + noise
        }
    }

    @Test func writtenSamplesComeBackBitForBit() async throws {
        let archive = tempArchive()
        let id = UUID()
        let info = RecordingInfo(date: Date(timeIntervalSince1970: 1_790_000_000), appName: "Терминал", bundleID: "com.apple.Terminal", modeID: "message")
        let writer = archive.start(id: id, info: info)
        let audio = samples(48_000)
        for chunk in stride(from: 0, to: audio.count, by: 1_600) {
            writer.append(Array(audio[chunk..<min(chunk + 1_600, audio.count)]))
        }
        await writer.finish()
        let url = archive.url(for: RecordingArchive.fileName(for: id))
        let read = try RecordingFile.samples(at: url)
        #expect(read.map(\.bitPattern) == audio.map(\.bitPattern))
        #expect(RecordingFile.info(at: url) == info)
        #expect(abs(RecordingFile.duration(at: url) - 3) < 0.0001)
    }

    @Test func coreAudioReadsTheSameSamples() async throws {
        let archive = tempArchive()
        let id = UUID()
        let writer = archive.start(id: id, info: RecordingInfo(date: Date()))
        let audio = samples(16_000, seed: 7)
        writer.append(audio)
        await writer.finish()
        let url = archive.url(for: RecordingArchive.fileName(for: id))
        let file = try AVAudioFile(forReading: url)
        #expect(file.fileFormat.sampleRate == 16_000)
        #expect(file.fileFormat.channelCount == 1)
        #expect(file.length == 16_000)
        let loaded = try AudioFileLoader.load(url)
        #expect(loaded.map(\.bitPattern) == audio.map(\.bitPattern))
        let player = try AVAudioPlayer(contentsOf: url)
        #expect(abs(player.duration - 1) < 0.01)
    }

    @Test func aRecordingCutByACrashIsReadableAndSealed() async throws {
        let archive = tempArchive()
        let id = UUID()
        let url = archive.url(for: RecordingArchive.fileName(for: id))
        let audio = samples(8_000, seed: 3)
        // What a killed process leaves: the header with an open-ended data chunk, the samples
        // written so far and half of the next one.
        try FileManager.default.createDirectory(at: archive.folder, withIntermediateDirectories: true)
        var bytes = RecordingFile.header(info: RecordingInfo(date: Date(timeIntervalSince1970: 1_790_000_000), appName: "Notes"))
        let headerSize = bytes.count
        audio.withUnsafeBufferPointer { bytes.append(Data(buffer: $0)) }
        bytes.append(contentsOf: [0x12, 0x34])
        try bytes.write(to: url)

        // Readable as it is, before anything repairs it.
        #expect(try RecordingFile.samples(at: url).count == 8_000)
        #expect(try AVAudioFile(forReading: url).length == 8_000)

        let (found, junk) = archive.recover(known: [])
        #expect(junk.isEmpty)
        #expect(found.count == 1)
        let record = try #require(found.first)
        #expect(record.id == id)
        #expect(record.failure == .interrupted)
        #expect(record.appName == "Notes")
        #expect(record.date == Date(timeIntervalSince1970: 1_790_000_000))
        #expect(abs(record.duration - 0.5) < 0.0001)
        #expect(record.audio == RecordingArchive.fileName(for: id))
        #expect(try RecordingFile.samples(at: url).map(\.bitPattern) == audio.map(\.bitPattern))
        let size = try #require(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
        // The half sample is trimmed and the data chunk carries its real size.
        #expect(size == headerSize + 8_000 * 4)
        #expect(try AVAudioFile(forReading: url).length == 8_000)
    }

    @Test func recoveryLeavesLinkedAndActiveRecordingsAlone() async throws {
        let archive = tempArchive()
        let linked = UUID()
        let active = UUID()
        let unlinked = UUID()
        let empty = UUID()
        for id in [linked, active, unlinked] {
            let writer = archive.start(id: id, info: RecordingInfo(date: Date()))
            writer.append(samples(1_600))
            await writer.finish()
        }
        let writer = archive.start(id: empty, info: RecordingInfo(date: Date()))
        await writer.finish()
        let records = [
            DictationRecord(id: linked, text: "текст", raw: "", appName: nil, bundleID: nil, duration: 0.1, date: Date(), audio: RecordingArchive.fileName(for: linked)),
            // The audio was dropped from this record, but deleting the file failed.
            DictationRecord(id: unlinked, text: "текст", raw: "", appName: nil, bundleID: nil, duration: 0.1, date: Date()),
        ]
        let (found, junk) = archive.recover(known: records, active: [active])
        #expect(found.isEmpty)
        #expect(junk == [unlinked, empty])
    }

    @Test func deleteRemovesOnlyTheGivenRecordings() async throws {
        let archive = tempArchive()
        let keep = UUID()
        let drop = UUID()
        for id in [keep, drop] {
            let writer = archive.start(id: id, info: RecordingInfo(date: Date()))
            writer.append(samples(160))
            await writer.finish()
        }
        archive.delete([drop])
        #expect(archive.files() == [RecordingArchive.fileName(for: keep)])
        archive.deleteAll()
        #expect(archive.files().isEmpty)
    }

    @Test func discardDeletesTheFile() async throws {
        let archive = tempArchive()
        let writer = archive.start(id: UUID(), info: RecordingInfo(date: Date()))
        writer.append(samples(1_600))
        await writer.discard()
        #expect(archive.files().isEmpty)
    }
}
