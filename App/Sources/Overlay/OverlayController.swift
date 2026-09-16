import AppKit
import Observation
import SwiftUI
import VMCore

/// Keeps the island or pill on screen in a panel that never becomes key, so the app the
/// user is typing into keeps focus.
///
/// The panel is larger than anything it draws. Clicks pass through it everywhere except
/// over the visible island or pill: the controller watches the pointer and flips
/// `ignoresMouseEvents` as it crosses that frame.
@MainActor
final class OverlayController {
    private let model: OverlayModel
    private let panel = OverlayPanel()
    private var monitors: [Any] = []
    private var tracking: Timer?
    private var lastStyle: AppSettings.OverlayStyle?

    static let islandPanelSize = CGSize(width: 540, height: 340)
    static let pillPanelSize = CGSize(width: 600, height: 360)

    init(model: OverlayModel) {
        self.model = model
        panel.contentView = ClickThroughHostingView(rootView: OverlayRoot(model: model))
        observe()
        installMonitors()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
        place()
        panel.orderFrontRegardless()
    }

    private var style: AppSettings.OverlayStyle { model.settings.value.overlayStyle }

    // MARK: State

    private func observe() {
        withObservationTracking {
            _ = model.dictation.phase
            _ = model.settings.value.overlayStyle
            _ = model.hover
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.update()
                self?.observe()
            }
        }
        update()
    }

    private var lastPhase: DictationController.Phase = .idle

    private func update() {
        let phase = model.dictation.phase
        if style != lastStyle {
            lastStyle = style
            model.collapse()
            place()
        }
        if phase == .listening, lastPhase != .listening {
            // Recording shows where the user is looking: the screen with the pointer.
            model.collapse()
            place()
        } else if phase == .idle, lastPhase != .idle {
            place()
        }
        lastPhase = phase
        panel.orderFrontRegardless()
        updateMouse()
    }

    // MARK: Placement

    private func place() {
        let screen = targetScreen()
        NotchMetrics.shared.update(for: screen)
        switch style {
        case .island:
            let size = Self.islandPanelSize
            panel.level = .statusBar + 3
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height), display: true)
        case .pill:
            let size = Self.pillPanelSize
            panel.level = .statusBar
            panel.setFrame(CGRect(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.minY + 8, width: size.width, height: size.height), display: true)
        }
    }

    /// While recording: the screen under the pointer. At rest the island lives on the
    /// screen with the notch and the pill on the screen with the menu bar.
    private func targetScreen() -> NSScreen {
        let screens = NSScreen.screens
        let pointer = NSEvent.mouseLocation
        let underPointer = screens.first { $0.frame.contains(pointer) }
        if model.dictation.phase != .idle, let underPointer { return underPointer }
        if style == .island, let notched = screens.first(where: { $0.auxiliaryTopLeftArea != nil }) { return notched }
        return screens.first ?? NSScreen.main ?? underPointer!
    }

    // MARK: Pointer

    private func installMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.updateMouse() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { event in
            handler(event)
            return event
        }) {
            monitors.append(local)
        }
    }

    /// Screen rectangle that should receive the pointer.
    private func hitRect() -> CGRect {
        let frame = model.hitFrame
        guard frame.width > 1 else { return .zero }
        let window = panel.frame
        var rect = CGRect(x: window.minX + frame.minX, y: window.maxY - frame.maxY, width: frame.width, height: frame.height)
        switch style {
        case .island:
            // The resting island is hidden behind the notch; only a notch is worth hovering.
            if model.dictation.phase == .idle, model.hover == .none {
                guard NotchMetrics.shared.hasNotch else { return .zero }
                rect = rect.insetBy(dx: -12, dy: -4)
            }
        case .pill:
            if model.dictation.phase == .idle, model.hover == .none {
                rect = rect.insetBy(dx: -34, dy: -14)
            }
        }
        return rect
    }

    private func updateMouse() {
        let inside = hitRect().contains(NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !inside
        if inside, !model.pointerInside {
            model.pointerEntered(opens: style == .island)
        } else if !inside, model.pointerInside {
            model.pointerExited()
        }
        // Mouse-moved events stop arriving once the pointer sits over our own panel in an
        // inactive app, so poll while it is there.
        let needsPolling = inside || model.hover != .none
        if needsPolling, tracking == nil {
            tracking = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateMouse() }
            }
        } else if !needsPolling, let timer = tracking {
            timer.invalidate()
            tracking = nil
        }
    }
}

struct OverlayRoot: View {
    let model: OverlayModel

    var body: some View {
        switch model.settings.value.overlayStyle {
        case .island:
            IslandView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .pill:
            PillView(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 6)
        }
    }
}

final class OverlayPanel: NSPanel {
    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Accepts the first click in an inactive panel, so drag and buttons work.
final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Size of the camera notch on the screen the overlay is on.
@MainActor
@Observable
final class NotchMetrics {
    static let shared = NotchMetrics()
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 32
    private(set) var hasNotch = false

    func update(for screen: NSScreen) {
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            width = screen.frame.width - left.width - right.width
            height = screen.safeAreaInsets.top
            hasNotch = true
        } else {
            width = 0
            height = NSStatusBar.system.thickness
            hasNotch = false
        }
    }
}
