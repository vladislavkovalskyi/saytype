import AVFoundation
import Foundation
import Observation

/// Plays kept recordings, one at a time. The History section and the card share it, so a
/// recording keeps playing while the user moves between them.
@MainActor
@Observable
final class RecordingPlayer {
    /// The record whose recording is loaded, playing or paused.
    private(set) var recordID: UUID?
    private(set) var isPlaying = false
    /// Seconds from the start.
    private(set) var position: Double = 0
    private(set) var length: Double = 0

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?

    var progress: Double { length > 0 ? min(1, position / length) : 0 }

    func isPlaying(_ id: UUID) -> Bool { recordID == id && isPlaying }

    /// Play, pause, or resume where it paused.
    func toggle(_ id: UUID, url: URL) {
        if recordID == id, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
                ticker?.cancel()
            } else {
                if player.currentTime >= player.duration - 0.05 { player.currentTime = 0 }
                start(player)
            }
            return
        }
        stop()
        // A file the cleanup took a moment ago plays nothing.
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        player.prepareToPlay()
        self.player = player
        recordID = id
        length = player.duration
        position = 0
        start(player)
    }

    /// Jumps to a point of the recording that is loaded, 0…1.
    func seek(_ id: UUID, to fraction: Double) {
        guard recordID == id, let player else { return }
        player.currentTime = max(0, min(1, fraction)) * player.duration
        position = player.currentTime
    }

    func stop() {
        ticker?.cancel()
        ticker = nil
        player?.stop()
        player = nil
        recordID = nil
        isPlaying = false
        position = 0
        length = 0
    }

    private func start(_ player: AVAudioPlayer) {
        player.play()
        isPlaying = true
        ticker?.cancel()
        // Twenty readouts a second move the progress bar; the end of the file stops the player.
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard let self, let player = self.player else { return }
                if player.isPlaying {
                    self.position = player.currentTime
                } else {
                    self.isPlaying = false
                    self.position = self.length
                    return
                }
            }
        }
    }
}
