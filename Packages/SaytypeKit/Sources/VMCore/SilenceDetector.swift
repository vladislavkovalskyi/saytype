import Foundation

/// Decides when hands-free recording has heard enough silence to stop by itself.
///
/// Levels are loudness on a −60…0 dBFS scale mapped to 0…1, so 0.1 is 6 dB. The detector tracks
/// the room's noise floor: it follows quieter levels within a fraction of a second and louder ones
/// over many seconds, so a fan or street noise becomes the floor while speech doesn't: every breath
/// brings the floor back down. A chunk is voice when it is clearly above the floor. Silence counts
/// after at least 0.2 s of continuous voice; a click or a cough only pauses the count. Before any
/// speech, recording stops after `initialLimit`. Constant work per chunk and no allocations.
public struct SilenceDetector: Sendable {
    /// Seconds of silence before stopping; 0 never stops.
    public var limit: Double

    /// Voice is this far above the noise floor, about 9 dB.
    static let voiceMargin: Float = 0.15
    /// Nothing below about −45 dBFS is voice, however quiet the room.
    static let minimumVoice: Float = 0.25
    /// Continuous voice that counts as speech rather than a click.
    static let speechOnset = 0.2
    /// Time constants of the noise floor, in seconds.
    static let floorFall = 0.25
    static let floorRise = 15.0

    private var floor: Float = -1
    private var voiceRun = 0.0
    private var silence = 0.0
    private var heardSpeech = false

    public init(limit: Double) {
        self.limit = limit
    }

    /// Before any speech, recording stops only after this much silence from the start.
    public var initialLimit: Double { max(limit * 2, 8) }

    /// Feeds the level of one audio chunk (0…1) lasting `duration` seconds.
    /// Returns true once the recording should stop.
    public mutating func update(level: Float, duration: Double) -> Bool {
        guard limit > 0, duration > 0 else { return false }
        // The first chunks can be digital zeros while the microphone starts.
        if floor < 0, level > 0 { floor = level }

        if floor >= 0, level >= Self.minimumVoice, level > floor + Self.voiceMargin {
            voiceRun += duration
            if voiceRun >= Self.speechOnset {
                heardSpeech = true
                silence = 0
            }
        } else {
            voiceRun = 0
            silence += duration
        }
        if floor >= 0 {
            let time = level < floor ? Self.floorFall : Self.floorRise
            floor += (level - floor) * Float(1 - exp(-duration / time))
        }
        return silence >= (heardSpeech ? limit : initialLimit)
    }
}
