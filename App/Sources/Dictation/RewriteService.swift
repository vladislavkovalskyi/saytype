import Foundation
import Observation
import VMCore

/// Rewrites and translations with a language model on this Mac: the built-in Qwen3 4B,
/// Ollama or LM Studio. Without a ready engine every call returns `nil` and the dictation
/// is inserted as formatted.
@MainActor
@Observable
final class RewriteService {
    enum State: Equatable {
        case off
        case missing
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var state = State.off

    /// True when a rewrite can run now.
    func isReady(_ settings: AppSettings) -> Bool {
        false
    }

    /// Loads the model when a dictation that needs it starts, so the final pass does not wait.
    func warmUp(_ settings: AppSettings) {}

    /// The rewritten text, or `nil` when the engine is off, slow, failed or dropped content.
    func rewrite(_ text: String, mode: DictationMode, settings: AppSettings) async -> String? {
        nil
    }
}
