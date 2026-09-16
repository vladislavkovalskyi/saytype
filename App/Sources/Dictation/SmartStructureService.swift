import Foundation
import Observation
import VMCore
import VMSmart

/// Smart structure: a local language model turns long dictations into lists and
/// paragraphs. Optional download; without it the deterministic formatter still works.
@MainActor
@Observable
final class SmartStructureService {
    enum State: Equatable {
        case missing
        case downloading(Double)
        case ready
        case failed(String)
    }

    private(set) var state = State.missing

    @ObservationIgnored private let store = SmartModelStore()
    @ObservationIgnored private lazy var structurer = SmartStructurer(store: store)
    @ObservationIgnored private var unloadTask: Task<Void, Never>?

    /// Past this the dictation is inserted without the model's structure.
    let timeout: Duration = .milliseconds(1500)
    /// The model leaves memory after this much idle time.
    let idleUnload: Duration = .seconds(300)
    /// Megabytes on disk, for the settings screen.
    let downloadSize = 944

    init() {
        state = store.isDownloaded ? .ready : .missing
    }

    /// The switch in settings: on when enabled and the model is on disk or downloading.
    func isOn(_ settings: AppSettings) -> Bool {
        settings.smartStructure && state != .missing
    }

    /// Turning the switch on downloads the model if it is not there yet.
    func turn(_ on: Bool, settings: SettingsStore) {
        settings.value.smartStructure = on
        guard on else { return }
        switch state {
        case .missing, .failed: download()
        case .downloading, .ready: break
        }
    }

    /// Short state line under the switch.
    var detail: String {
        switch state {
        case .missing: "Qwen3 1.7B · " + String(localized: "\(downloadSize) MB")
        case .downloading(let fraction): String(localized: "downloading", comment: "Smart structure model state, followed by a percentage") + " · \(Int(fraction * 100))%"
        case .ready: "Qwen3 1.7B · " + String(localized: "lists and paragraphs", comment: "What the smart structure model does")
        case .failed: String(localized: "download failed, turn it on again", comment: "Smart structure model state under its switch")
        }
    }

    func download() {
        if case .downloading = state { return }
        state = .downloading(0)
        let store = store
        Task {
            do {
                try await store.download { fraction in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloading = self.state else { return }
                        self.state = .downloading(fraction)
                    }
                }
                state = store.isDownloaded ? .ready : .failed(String(localized: "Download did not finish"))
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func remove() {
        let structurer = structurer
        Task {
            await structurer.unload()
            try? store.remove()
            state = .missing
        }
    }

    /// Loads the model in the background when the user starts talking, so the final
    /// pass does not pay the load time.
    func warmUp(settings: AppSettings) {
        guard settings.smartStructure, state == .ready else { return }
        unloadTask?.cancel()
        let structurer = structurer
        Task.detached(priority: .utility) { try? await structurer.load() }
    }

    /// Structured text, or `text` unchanged when the model is off, slow or unsure.
    func apply(to text: String, settings: AppSettings) async -> String {
        guard settings.smartStructure, settings.punctuation, state == .ready,
              SmartStructure.shouldStructure(text, minWords: settings.smartStructureMinWords)
        else { return text }

        let structurer = structurer
        // Loading takes seconds and cannot be interrupted; this dictation goes without it.
        guard await structurer.isLoaded else {
            warmUp(settings: settings)
            return text
        }
        let allowDroppingFillers = settings.fillerMode == .all
        let timeout = timeout
        let result = await withTaskGroup(of: String?.self) { group in
            group.addTask { try? await structurer.structure(text, allowDroppingFillers: allowDroppingFillers) }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        scheduleUnload()
        return result ?? text
    }

    private func scheduleUnload() {
        unloadTask?.cancel()
        let structurer = structurer
        let idle = idleUnload
        unloadTask = Task {
            try? await Task.sleep(for: idle)
            guard !Task.isCancelled else { return }
            await structurer.unload()
        }
    }
}
