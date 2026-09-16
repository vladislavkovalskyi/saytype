import Foundation

/// One recognised word with its position in the recording, in seconds.
public struct TranscriptWord: Sendable, Equatable, Codable {
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
    /// Empty when the engine does not report word timings.
    public var words: [TranscriptWord]

    public init(text: String, words: [TranscriptWord] = []) {
        self.text = text
        self.words = words
    }

    public static let empty = Transcript(text: "")
}
