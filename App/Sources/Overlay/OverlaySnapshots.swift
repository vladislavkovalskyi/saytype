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
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--benchmark") {
            let frames = i + 1 < arguments.count ? Int(arguments[i + 1]) ?? 480 : 480
            benchmark(frames: frames, model: model, into: folder)
            return
        }
        let terminal = DictationController.TargetApp(name: "Terminal", bundleID: "com.apple.Terminal", icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app"))
        let committed = "поправь useEffect в Header, он"
        let pending = "дёргается при"
        let long = "поправь useEffect в Header, он дёргается при каждом рендере и сбрасывает"
        let card = "Сегодня три дела:\n1. Обнови Next.js.\n2. Задеплой feature/auth на Vercel.\n3. Скинь превью."

        let shots: [Shot] = [
            Shot("1-idle", .idle),
            Shot("2-peek", .idle, hover: .peek),
            Shot("3-panel", .idle, hover: .open),
            Shot("3b-panel-mode-fixed", .idle, hover: .open, fixedMode: DictationMode.promptID),
            Shot("3c-panel-translating", .idle, hover: .open, translate: true),
            Shot("4-listening-start", .listening),
            Shot("4b-listening-start-mode", .listening, mode: DictationMode.promptID, handsFree: true),
            Shot("5-listening", .listening, committed: committed, pending: pending),
            Shot("5b-listening-two-lines", .listening, committed: long, pending: "состояние формы"),
            Shot("5c-listening-mode", .listening, committed: committed, pending: pending, mode: DictationMode.messageID),
            Shot("5d-listening-mode-hands-free", .listening, committed: long, pending: "формы", mode: DictationMode.promptID, handsFree: true),
            Shot("6-finishing", .finishing, committed: committed, pending: pending),
            Shot("6b-rewriting", .finishing, committed: long, pending: "", mode: DictationMode.commitID, stage: .rewriting),
            Shot("6c-rewriting-no-live-text", .finishing, mode: DictationMode.commitID, stage: .rewriting),
            Shot("7-inserted", .inserted(terminal)),
            Shot("8-notice", .notice(.passwordField)),
            Shot("8b-notice-mode", .notice(.mode(DictationMode(id: DictationMode.promptID).title))),
            Shot("8c-notice-nothing-selected", .notice(.nothingSelected)),
            Shot("8d-notice-model-off", .notice(.modelOff)),
            Shot("9-card", .card(card)),
            Shot("9b-card-editing", .card(card), editing: card.replacingOccurrences(of: "Next.js", with: "некст джей эс")),
            Shot("9c-card-learned", .card(card), learned: [DictionaryEntry(heard: "некст джей эс", written: "Next.js", source: .history)]),
        ]
        let transparent = arguments.contains("--transparent")
        for style in [AppSettings.OverlayStyle.island, .pill] {
            settings.value.overlayStyle = style
            for shot in shots {
                apply(shot, to: model)
                if case .card = shot.phase { dictation.demoCardShortcuts() }
                render(root(model, style: style, transparent: transparent), size: panelSize(style), to: folder.appending(path: "\(style.rawValue)-\(shot.name).png"))
            }
        }

        // Frames in the middle of transitions, with the hit frame each one reports.
        let transitions: [(String, Shot, Shot)] = [
            ("peek-to-panel", Shot("", .idle, hover: .peek), Shot("", .idle, hover: .open)),
            ("start-to-text", Shot("", .listening), Shot("", .listening, committed: committed, pending: pending)),
            ("one-to-two-lines", Shot("", .listening, committed: committed, pending: pending), Shot("", .listening, committed: long, pending: "состояние")),
            ("listening-to-rewriting", Shot("", .listening, committed: committed, pending: pending, mode: DictationMode.commitID), Shot("", .finishing, committed: committed, pending: pending, mode: DictationMode.commitID, stage: .rewriting)),
            ("finishing-to-inserted", Shot("", .finishing, committed: long, pending: ""), Shot("", .inserted(terminal))),
        ]
        var log: [String] = []
        for style in [AppSettings.OverlayStyle.island, .pill] {
            settings.value.overlayStyle = style
            for (name, from, to) in transitions {
                log += renderTransition(from: from, to: to, model: model, style: style, transparent: transparent, name: "\(style.rawValue)-t-\(name)", folder: folder)
            }
        }
        try? log.joined(separator: "\n").write(to: folder.appending(path: "transitions.txt"), atomically: true, encoding: .utf8)
        apply(Shot("", .idle), to: model)
    }

    /// One overlay state for a snapshot.
    private struct Shot {
        let name: String
        let phase: DictationController.Phase
        var hover = OverlayModel.Hover.none
        var committed = ""
        var pending = ""
        var mode = DictationMode.standardID
        var stage = DictationController.FinishingStage.transcribing
        var handsFree = false
        var fixedMode: String?
        /// Every dictation is translated.
        var translate = false
        /// The card is open for editing, with this draft in its field.
        var editing: String?
        /// What the last edit taught the dictionary.
        var learned: [DictionaryEntry] = []

        init(_ name: String, _ phase: DictationController.Phase, hover: OverlayModel.Hover = .none, committed: String = "", pending: String = "", mode: String = DictationMode.standardID, stage: DictationController.FinishingStage = .transcribing, handsFree: Bool = false, fixedMode: String? = nil, translate: Bool = false, editing: String? = nil, learned: [DictionaryEntry] = []) {
            self.name = name
            self.phase = phase
            self.hover = hover
            self.committed = committed
            self.pending = pending
            self.mode = mode
            self.stage = stage
            self.handsFree = handsFree
            self.fixedMode = fixedMode
            self.translate = translate
            self.editing = editing
            self.learned = learned
        }
    }

    private static func apply(_ shot: Shot, to model: OverlayModel) {
        let settings = model.settings
        let mode = settings.value.modes.first { $0.id == shot.mode } ?? DictationMode(id: shot.mode)
        // A mode picked by hand, so the chips never depend on the app in front of this Mac.
        settings.value.fixedModeID = shot.fixedMode ?? DictationMode.standardID
        settings.value.autoTranslate = shot.translate
        model.dictation.demoMode(mode, stage: shot.stage, handsFree: shot.handsFree)
        model.dictation.demoSet(phase: shot.phase, committed: shot.committed, pending: shot.pending)
        model.dictation.demoCardEdit(shot.editing)
        model.dictation.demoLearned(shot.learned)
        model.setHoverForSnapshot(shot.hover)
    }

    private static func panelSize(_ style: AppSettings.OverlayStyle) -> CGSize {
        style == .island ? OverlayController.islandPanelSize : OverlayController.pillPanelSize
    }

    private static func root(_ model: OverlayModel, style: AppSettings.OverlayStyle, transparent: Bool) -> some View {
        let size = panelSize(style)
        return OverlayRoot(model: model)
            .frame(width: size.width, height: size.height)
            .background(transparent ? AnyShapeStyle(Color.clear) : AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x3B5566), Color(hex: 0x5A2E3E)], startPoint: .top, endPoint: .bottom)))
    }

    /// Settles on `from`, switches to `to` and draws frames at fixed times after the switch. The
    /// raster itself takes a few milliseconds, so each file is named by the time it was taken.
    private static func renderTransition(from: Shot, to: Shot, model: OverlayModel, style: AppSettings.OverlayStyle, transparent: Bool, name: String, folder: URL) -> [String] {
        let size = panelSize(style)
        apply(from, to: model)
        let host = NSHostingView(rootView: root(model, style: style, transparent: transparent))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.9))
        apply(to, to: model)
        let start = Date()
        var log: [String] = []
        for time in [0.0, 0.04, 0.08, 0.12, 0.18, 0.26, 0.4, 0.9] {
            RunLoop.main.run(until: start.addingTimeInterval(time))
            host.layoutSubtreeIfNeeded()
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            let frame = model.hitFrame
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: folder.appending(path: String(format: "%@-%04dms.png", name, elapsed)))
            log.append(String(format: "%@ %4d ms: hit frame x %.1f y %.1f w %.1f h %.1f", name, elapsed, frame.minX, frame.minY, frame.width, frame.height))
        }
        window.contentView = nil
        return log
    }

    /// `--snapshot-overlays <folder> --benchmark [frames]`: plays the listening island and pill
    /// offscreen for `frames` frames at a 120 Hz pace, with a new audio level every 4th frame and a
    /// new word every 0.9 s, and prints the CPU time per frame. "Main thread" is everything SwiftUI
    /// and AppKit do there, animation ticks included; "process" adds render threads. Waiting between
    /// frames costs nothing. A CPU raster of one frame is timed separately; the real panel draws on
    /// the GPU, so it is only an upper bound.
    private static func benchmark(frames: Int, model: OverlayModel, into folder: URL) {
        let dictation = model.dictation
        let settings = model.settings
        let words = "поправь useEffect в Header, он дёргается при каждом рендере и сбрасывает состояние формы".split(separator: " ").map(String.init)
        let scenarios: [(String, AppSettings.OverlayStyle, DictationController.Phase)] = [
            ("island listening", .island, .listening),
            ("pill listening", .pill, .listening),
            ("island finishing", .island, .finishing),
            ("island idle", .island, .idle),
            ("pill idle", .pill, .idle),
        ]
        var report: [String] = []
        for (name, style, phase) in scenarios {
            settings.value.overlayStyle = style
            model.setHoverForSnapshot(.none)
            dictation.demoSet(phase: phase, committed: phase == .idle ? "" : words.prefix(6).joined(separator: " "), pending: "")
            let size = style == .island ? OverlayController.islandPanelSize : OverlayController.pillPanelSize
            let host = NSHostingView(rootView: OverlayRoot(model: model).frame(width: size.width, height: size.height))
            host.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = host
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))

            let mainStart = Self.threadCPU()
            let processStart = Self.processCPU()
            let wallStart = Date()
            for frame in 0..<frames {
                let due = wallStart.addingTimeInterval(Double(frame + 1) / 120)
                if phase == .listening {
                    if frame % 4 == 0 { dictation.demoLevels() }
                    if frame % 108 == 107 {
                        let count = 6 + (frame / 108 + 1) % (words.count - 6)
                        dictation.demoSet(phase: phase, committed: words.prefix(count - 2).joined(separator: " "), pending: words[(count - 2)..<count].joined(separator: " "))
                    }
                }
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                CATransaction.flush()
                RunLoop.main.run(until: due)
            }
            let main = (Self.threadCPU() - mainStart) / Double(frames)
            let process = (Self.processCPU() - processStart) / Double(frames)

            var raster: [Double] = []
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                for _ in 0..<12 {
                    let start = Self.threadCPU()
                    host.cacheDisplay(in: host.bounds, to: rep)
                    raster.append(Self.threadCPU() - start)
                }
            }
            window.contentView = nil
            let line = String(format: "%@: %d frames, main thread %.3f ms/frame, process %.3f ms/frame, CPU raster %.1f ms", name, frames, main, process, Self.mean(raster))
            print(line)
            report.append(line)
        }
        try? report.joined(separator: "\n").write(to: folder.appending(path: "benchmark.txt"), atomically: true, encoding: .utf8)
    }

    /// CPU time of the calling thread, in milliseconds.
    private static func threadCPU() -> Double {
        var time = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
        return Double(time.tv_sec) * 1000 + Double(time.tv_nsec) / 1e6
    }

    /// CPU time of the whole process, all threads, in milliseconds.
    private static func processCPU() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func ms(_ t: timeval) -> Double { Double(t.tv_sec) * 1000 + Double(t.tv_usec) / 1000 }
        return ms(usage.ru_utime) + ms(usage.ru_stime)
    }

    private static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
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
