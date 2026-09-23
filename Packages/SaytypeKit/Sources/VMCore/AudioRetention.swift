import Foundation

extension AppSettings {
    /// How long the recordings of recent dictations stay on this Mac.
    public enum AudioRetention: String, Codable, CaseIterable, Sendable {
        /// No recording is written at all.
        case off
        case day
        case week

        /// Age after which a recording goes; `nil` when nothing is kept.
        public var period: TimeInterval? {
            switch self {
            case .off: nil
            case .day: 86_400
            case .week: 7 * 86_400
            }
        }
    }
}

/// Which recordings stay and which go. The history is newest first; a recording stays while it
/// is younger than the period and among the `limit` newest recordings.
public enum AudioKeeping {
    public static let defaultLimit = 20

    /// Records whose audio goes now.
    public static func expired(_ records: [DictationRecord], retention: AppSettings.AudioRetention, limit: Int, now: Date = Date()) -> Set<UUID> {
        let withAudio = records.filter { $0.audio != nil }
        guard let period = retention.period, limit > 0 else { return Set(withAudio.map(\.id)) }
        let cutoff = now.addingTimeInterval(-period)
        var kept = 0
        var expired = Set<UUID>()
        for record in withAudio.sorted(by: { $0.date > $1.date }) {
            if record.date >= cutoff, kept < limit {
                kept += 1
            } else {
                expired.insert(record.id)
            }
        }
        return expired
    }

    /// Recording ids in the audio folder that no record points to and no recording in progress
    /// owns. `files` are file names such as "<uuid>.caf" or "<uuid>.json".
    public static func strays(files: [String], records: [DictationRecord], active: Set<UUID>) -> Set<UUID> {
        let linked = Set(records.compactMap { record in record.audio.map { _ in record.id } })
        var result = Set<UUID>()
        for file in files {
            guard let id = recordingID(file), !linked.contains(id), !active.contains(id) else { continue }
            result.insert(id)
        }
        return result
    }

    /// "3F2…9A.caf" → the UUID; `nil` for a file that is not a recording's.
    public static func recordingID(_ file: String) -> UUID? {
        guard let stem = file.split(separator: ".", maxSplits: 1).first else { return nil }
        return UUID(uuidString: String(stem))
    }
}
