import AppKit
import SwiftUI

/// Owns the main and onboarding windows. They are plain AppKit windows with a
/// transparent title bar so the colour world runs edge to edge.
@MainActor
final class WindowManager {
    private unowned let model: AppModel
    private var main: NSWindow?
    private var onboarding: NSWindow?

    init(model: AppModel) {
        self.model = model
    }

    func showMain() {
        if main == nil {
            // The main window's 740 pt include the transparent title bar, as in the mockups.
            main = makeWindow(size: CGSize(width: 1180, height: 740), root: MainWindow().environment(model), titleBarInside: true)
        }
        present(main)
    }

    func showOnboarding() {
        if onboarding == nil {
            onboarding = makeWindow(size: CGSize(width: 960, height: 640), root: OnboardingWindow().environment(model))
        }
        present(onboarding)
    }

    func closeOnboarding() {
        onboarding?.close()
        onboarding = nil
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        if AppModel.isPreviewLaunch {
            // Screenshots shouldn't take keyboard focus from whatever the user is doing.
            window.orderFrontRegardless()
            return
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// `size` is the whole window, title bar included. `titleBarInside` lets the content
    /// run under the transparent title bar instead of starting below it.
    private func makeWindow(size: CGSize, root: some View, titleBarInside: Bool = false) -> NSWindow {
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: root)
        if titleBarInside {
            hosting.safeAreaRegions = []
        }
        window.contentView = hosting
        // The content rect excludes the title bar; the design sizes include it.
        window.setFrame(CGRect(origin: .zero, size: size), display: false)
        window.center()
        // Previews are for screenshots: put them on the sharpest screen.
        if AppModel.isPreviewLaunch, let screen = NSScreen.screens.max(by: { $0.backingScaleFactor < $1.backingScaleFactor }) {
            let visible = screen.visibleFrame
            window.setFrameOrigin(CGPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        return window
    }
}
