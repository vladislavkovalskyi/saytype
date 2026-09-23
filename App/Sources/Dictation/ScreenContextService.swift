import AppKit
import Observation
import VMCore
import VMSystem

/// Terms from the window in front: read in the background when a dictation starts, handed to the
/// final pass when it ends, then dropped.
///
/// The window's text never leaves the reading task; only the terms do, and they live until the
/// next dictation. What the last dictation changed stays for the readout in Dictionary.
@MainActor
@Observable
final class ScreenContextService {
    /// Terms the last dictation took from the screen, best first.
    private(set) var lastUsed: [String] = []
    /// How many terms the last dictation had to choose from.
    private(set) var lastRead = 0

    @ObservationIgnored private var pending: Task<[String], Never>?
    /// A read was started for the dictation being recorded; an Edit selection one has none.
    @ObservationIgnored private var started = false

    init() {
        if AppModel.isPreviewLaunch {
            // Screenshots show the readout with made-up terms; previews never read a window.
            lastUsed = ["DictationController", "PromptBuilder.swift"]
            lastRead = 18
        }
    }

    /// Starts reading the app in front. Returns at once; the recording is never held up.
    func begin(enabled: Bool) {
        cancel()
        guard enabled, !AppModel.isPreviewLaunch, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        let pid = app.processIdentifier
        started = true
        pending = Task.detached(priority: .userInitiated) {
            ScreenTerms.extract(from: ScreenContextReader.read(pid: pid).text)
        }
    }

    /// The terms for the dictation being finished. The read is long over by the time the key is
    /// released; if it is not, this waits for its deadline.
    func take() async -> [String] {
        guard let pending else { return [] }
        self.pending = nil
        return await pending.value
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        started = false
    }

    /// Keeps what the dictation took from the screen: terms in the text that Whisper did not write.
    /// A dictation that read nothing leaves the last readout as it was.
    func record(terms: [String], raw: String, text: String) {
        guard started else { return }
        started = false
        lastRead = terms.count
        lastUsed = terms.filter { text.contains($0) && !raw.contains($0) }
    }
}
