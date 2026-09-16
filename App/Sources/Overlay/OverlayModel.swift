import AppKit
import Observation
import SwiftUI
import VMCore

/// Hover state of the island and the pill, shared by both views and the controller.
///
/// Hovering the notch lifts the island right away (`peek`); holding the pointer there
/// for 0.3 s opens the panel. Leaving closes it after 0.35 s, unless a menu from the
/// panel is open.
@MainActor
@Observable
final class OverlayModel {
    enum Hover: Equatable {
        case none
        case peek
        case open
    }

    private(set) var hover = Hover.none
    /// Frame of the visible island or pill in the panel's view coordinates, for hit testing.
    var hitFrame: CGRect = .zero
    /// A popup menu from the panel is on screen; the panel must not close under it.
    var menuOpen = false {
        didSet { if !menuOpen, !pointerInside { pointerExited() } }
    }

    let dictation: DictationController
    let settings: SettingsStore
    let openMain: (MainSection) -> Void
    let smartStructure: Binding<Bool>

    @ObservationIgnored private var openTask: Task<Void, Never>?
    @ObservationIgnored private var closeTask: Task<Void, Never>?
    @ObservationIgnored private(set) var pointerInside = false

    static let openDelay: Duration = .milliseconds(300)
    static let closeDelay: Duration = .milliseconds(350)

    init(dictation: DictationController, settings: SettingsStore, openMain: @escaping (MainSection) -> Void, smartStructure: Binding<Bool>) {
        self.dictation = dictation
        self.settings = settings
        self.openMain = openMain
        self.smartStructure = smartStructure
    }

    /// Hover only matters while nothing is being dictated.
    var acceptsHover: Bool {
        switch dictation.phase {
        case .idle, .inserted, .notice: true
        case .listening, .finishing, .card: false
        }
    }

    func pointerEntered(opens: Bool) {
        pointerInside = true
        closeTask?.cancel()
        guard acceptsHover else { return }
        if hover == .none { hover = .peek }
        guard opens, hover == .peek, openTask == nil else { return }
        openTask = Task { [weak self] in
            try? await Task.sleep(for: Self.openDelay)
            guard let self, !Task.isCancelled else { return }
            self.openTask = nil
            if self.hover == .peek, self.pointerInside, self.acceptsHover { self.hover = .open }
        }
    }

    func pointerExited() {
        pointerInside = false
        openTask?.cancel()
        openTask = nil
        guard hover != .none, !menuOpen else { return }
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: Self.closeDelay)
            guard let self, !Task.isCancelled, !self.pointerInside, !self.menuOpen else { return }
            self.hover = .none
        }
    }

    func setHoverForSnapshot(_ hover: Hover) {
        self.hover = hover
    }

    func collapse() {
        openTask?.cancel()
        openTask = nil
        closeTask?.cancel()
        hover = .none
    }

    /// Runs a native menu from the panel; the panel stays open until the menu closes.
    func withMenu(_ show: () -> Void) {
        menuOpen = true
        show()
        menuOpen = false
    }
}

extension DictationController.Notice {
    var title: LocalizedStringKey {
        switch self {
        case .passwordField: "Password field"
        case .modelMissing: "Model not downloaded"
        case .modelFailed: "Model failed to load"
        case .microphoneUnavailable: "Microphone unavailable"
        case .recognitionFailed: "Couldn't transcribe"
        case .nothingHeard: "Nothing heard"
        case .copied: "Copied"
        }
    }

    var symbol: String {
        switch self {
        case .passwordField: "lock.fill"
        case .modelMissing, .modelFailed: "cpu"
        case .microphoneUnavailable: "mic.slash.fill"
        case .recognitionFailed, .nothingHeard: "waveform.slash"
        case .copied: "doc.on.doc.fill"
        }
    }

    /// Plain string for measuring how wide the island must grow.
    var measuredTitle: String {
        switch self {
        case .passwordField: String(localized: "Password field")
        case .modelMissing: String(localized: "Model not downloaded")
        case .modelFailed: String(localized: "Model failed to load")
        case .microphoneUnavailable: String(localized: "Microphone unavailable")
        case .recognitionFailed: String(localized: "Couldn't transcribe")
        case .nothingHeard: String(localized: "Nothing heard")
        case .copied: String(localized: "Copied")
        }
    }
}
