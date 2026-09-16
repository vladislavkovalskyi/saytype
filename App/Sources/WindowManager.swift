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
            main = makeWindow(size: CGSize(width: 1180, height: 740), root: MainWindow().environment(model))
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
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(size: CGSize, root: some View) -> NSWindow {
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
        window.contentView = NSHostingView(rootView: root)
        window.center()
        return window
    }
}
