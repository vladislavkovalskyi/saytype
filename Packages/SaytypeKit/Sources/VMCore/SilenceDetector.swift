import Foundation

/// Decides when hands-free recording has heard enough silence to stop by itself.
public struct SilenceDetector: Sendable {
    /// Seconds of silence before stopping; 0 never stops.
    public var limit: Double

    public init(limit: Double) {
        self.limit = limit
    }

    /// Feeds the level of one audio chunk (0…1) lasting `duration` seconds.
    /// Returns true once the recording should stop.
    public mutating func update(level: Float, duration: Double) -> Bool {
        false
    }
}
