import Foundation

/// A stretch of speech Whisper closed with timestamps, usually a sentence or two, with its
/// position in the recording in seconds.
public struct TranscriptSegment: Sendable, Equatable, Codable {
    public var text: String
    public var start: Double
    public var end: Double

    public init(text: String, start: Double, end: Double) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// What an engine heard, before any formatting.
public struct Transcript: Sendable, Equatable, Codable {
    public var text: String
    /// The text in timed pieces; empty when the engine does not report timings.
    public var segments: [TranscriptSegment]

    public init(text: String, segments: [TranscriptSegment] = []) {
        self.text = text
        self.segments = segments
    }

    public static let empty = Transcript(text: "")
}
