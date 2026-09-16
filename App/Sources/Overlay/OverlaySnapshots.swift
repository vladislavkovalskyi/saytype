import AppKit
import SwiftUI
import VMCore

/// Renders every island and pill state to PNG files without putting a window on screen:
/// `saytype --snapshot-overlays <folder>`. For checking the design while the real app runs.
@MainActor
enum OverlaySnapshots {
    static func run(into folder: URL, model app: AppModel) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let dictation = app.dictation
        let settings = app.settings
        let model = OverlayModel(dictation: dictation, settings: settings, openMain: { _ in }, smartStructure: .constant(true))
        if let notched = NSScreen.screens.first(where: { $0.auxiliaryTopLeftArea != nil }) ?? NSScreen.main {
            NotchMetrics.shared.update(for: notched)
        }
        dictation.demoHistory(DictationController.sampleHistory())
        dictation.demoModelReady()
        dictation.demoLevels()
        let terminal = DictationController.TargetApp(name: "Terminal", bundleID: "com.apple.Terminal", icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app"))
        let committed = "поправь useEffect в Header, он"
        let pending = "дёргается при"
        let card = "Сегодня три дела:\n1. Обнови Next.js.\n2. Задеплой feature/auth на Vercel.\n3. Скинь превью."

        let states: [(String, DictationController.Phase, OverlayModel.Hover, String, String)] = [
            ("1-idle", .idle, .none, "", ""),
            ("2-peek", .idle, .peek, "", ""),
            ("3-panel", .idle, .open, "", ""),
            ("4-listening-start", .listening, .none, "", ""),
            ("5-listening", .listening, .none, committed, pending),
            ("6-finishing", .finishing, .none, committed, pending),
            ("7-inserted", .inserted(terminal), .none, "", ""),
            ("8-notice", .notice(.passwordField), .none, "", ""),
            ("9-card", .card(card), .none, "", ""),
        ]
        for style in [AppSettings.OverlayStyle.island, .pill] {
            settings.value.overlayStyle = style
            for (name, phase, hover, committed, pending) in states {
                dictation.demoSet(phase: phase, committed: committed, pending: pending)
                if case .card = phase { dictation.demoCardShortcuts() }
                model.setHoverForSnapshot(hover)
                let size = style == .island ? OverlayController.islandPanelSize : OverlayController.pillPanelSize
                let transparent = ProcessInfo.processInfo.arguments.contains("--transparent")
                let root = OverlayRoot(model: model)
                    .frame(width: size.width, height: size.height)
                    .background(transparent ? AnyShapeStyle(Color.clear) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3B5566), Color(hex: 0x5A2E3E)], startPoint: .top, endPoint: .bottom)))
                render(root, size: size, to: folder.appending(path: "\(style.rawValue)-\(name).png"))
            }
        }
    }

    private static func render(_ view: some View, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        // Let onAppear animations (the check mark, spinners) settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.7))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.contentView = nil
    }
}
