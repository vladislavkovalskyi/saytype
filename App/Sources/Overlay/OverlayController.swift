import AppKit
import Observation
import SwiftUI
import VMCore

/// Shows dictation state in a panel that never becomes key, so the app the user
/// is typing into keeps focus.
@MainActor
final class OverlayController {
    private let dictation: DictationController
    private let settings: SettingsStore
    private let panel: OverlayPanel

    static let islandSize = CGSize(width: 760, height: 280)
    static let pillSize = CGSize(width: 820, height: 300)

    init(dictation: DictationController, settings: SettingsStore) {
        self.dictation = dictation
        self.settings = settings
        panel = OverlayPanel()
        let root = OverlayRoot(dictation: dictation, settings: settings)
        let host = ClickThroughHostingView(rootView: root)
        panel.contentView = host
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = dictation.phase
            _ = settings.value.overlayStyle
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
        update()
    }

    private func update() {
        let phase = dictation.phase
        if phase == .idle {
            // Leave the panel up briefly so the collapse animation can play.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, self.dictation.phase == .idle else { return }
                self.panel.orderOut(nil)
            }
            return
        }
        if phase == .listening || !panel.isVisible {
            place()
        }
        if case .card = phase {
            panel.ignoresMouseEvents = false
        } else {
            panel.ignoresMouseEvents = true
        }
        panel.orderFrontRegardless()
    }

    private func place() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        switch settings.value.overlayStyle {
        case .island:
            let size = Self.islandSize
            panel.level = .statusBar + 3
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        case .pill:
            let size = Self.pillSize
            panel.level = .floating
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 12, width: size.width, height: size.height), display: true)
        }
        NotchMetrics.shared.update(for: screen)
    }
}

final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepts the first click in an inactive panel, so drag and buttons on the card work.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Size of the camera notch on the screen the overlay is on. Zero when the screen has none.
@MainActor
@Observable
final class NotchMetrics {
    static let shared = NotchMetrics()
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 32

    func update(for screen: NSScreen) {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = screen.frame.width - left.width - right.width
            height = screen.safeAreaInsets.top
        } else {
            width = 0
            height = NSStatusBar.system.thickness
        }
    }
}
