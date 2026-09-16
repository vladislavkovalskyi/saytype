import Foundation

/// Decides which live words are stable enough to show as final.
///
/// Whisper re-decodes the growing recording about once a second and may revise
/// its last words. A word is committed once two consecutive hypotheses agree on
/// everything up to and including it (LocalAgreement-2). Committed words never
/// disappear, so the overlay text does not jump backwards.
public struct LiveAgreement: Sendable, Equatable {
    public private(set) var committed: [String] = []
    public private(set) var pending: [String] = []
    private var previous: [String] = []

    public init() {}

    /// Feeds a hypothesis for the whole utterance so far.
    public mutating func update(with hypothesis: String) {
        let words = Words.split(hypothesis)
        let agreed = Self.commonPrefixLength(previous, words)
        if agreed > committed.count {
            committed = Array(words.prefix(agreed))
        }
        // The new hypothesis may be shorter than what was already committed.
        pending = words.count > committed.count ? Array(words.dropFirst(committed.count)) : []
        previous = words
    }

    public var committedText: String { committed.joined(separator: " ") }
    public var pendingText: String { pending.joined(separator: " ") }

    static func commonPrefixLength(_ a: [String], _ b: [String]) -> Int {
        var n = 0
        while n < a.count, n < b.count, Words.key(a[n]) == Words.key(b[n]) {
            n += 1
        }
        return n
    }
}
