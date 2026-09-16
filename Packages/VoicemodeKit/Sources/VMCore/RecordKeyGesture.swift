import Foundation

/// Turns raw key presses of the record key into dictation commands.
///
/// - Holding the key records until release.
/// - A press shorter than `tapThreshold` is a tap: its recording is discarded.
/// - Two taps in quick succession start hands-free recording; the next press stops it.
/// - Esc, or any other key pressed while the record key is down, cancels.
public struct RecordKeyGesture: Sendable {
    public enum Input: Sendable, Equatable {
        case keyDown(TimeInterval)
        case keyUp(TimeInterval)
        /// Esc.
        case escape
        /// Any other key while the record key is held, like fn+arrow.
        case otherKey
    }

    public enum Command: Sendable, Equatable {
        case startRecording
        case finishRecording
        case cancelRecording
        case startHandsFree
    }

    public var tapThreshold: TimeInterval = 0.3
    public var doubleTapWindow: TimeInterval = 0.35
    public var handsFreeEnabled = true

    private enum Phase: Equatable {
        case idle
        case holding(since: TimeInterval)
        case handsFree
    }

    private var phase = Phase.idle
    private var lastTapEnd: TimeInterval?

    public init() {}

    public mutating func handle(_ input: Input) -> Command? {
        switch (input, phase) {
        case (.keyDown(let t), .idle):
            if handsFreeEnabled, let lastTapEnd, t - lastTapEnd <= doubleTapWindow {
                self.lastTapEnd = nil
                phase = .handsFree
                return .startHandsFree
            }
            phase = .holding(since: t)
            return .startRecording

        case (.keyDown, .handsFree):
            phase = .idle
            return .finishRecording

        case (.keyUp(let t), .holding(let since)):
            phase = .idle
            if t - since < tapThreshold {
                lastTapEnd = t
                return .cancelRecording
            }
            lastTapEnd = nil
            return .finishRecording

        case (.escape, .holding), (.escape, .handsFree), (.otherKey, .holding):
            phase = .idle
            lastTapEnd = nil
            return .cancelRecording

        default:
            return nil
        }
    }

    public var isRecording: Bool { phase != .idle }
}
