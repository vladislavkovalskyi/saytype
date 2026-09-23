import AppKit
import SwiftUI

/// Renders a section of the main window to a PNG without putting a window on screen:
/// `saytype --snapshot-main history out.png`. Sample history and default settings, like every
/// preview launch. The History section gets two more files: a recording without text selected
/// (`-untranscribed`) and a re-transcription running (`-retranscribing`).
@MainActor
enum MainSnapshots {
    static func run(section: MainSection, into url: URL, model: AppModel) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dictation = model.dictation
        dictation.activate(listening: false)
        model.mainSection = section
        render(model, to: url)
        guard section == .history else { return }

        let records = dictation.records
        let base = url.deletingPathExtension().path
        if let lost = records.firstIndex(where: { !$0.isTranscribed }) {
            // The section selects the newest record; put the one without text first.
            var reordered = records
            reordered.insert(reordered.remove(at: lost), at: 0)
            dictation.demoHistory(reordered)
            render(model, to: URL(fileURLWithPath: base + "-untranscribed.png"))
            dictation.demoHistory(records)
        }
        if let first = records.first {
            dictation.retranscription = Retranscription(recordID: first.id, state: .loading(DictationController.modelTitle(WhisperModelInfo.large)))
            render(model, to: URL(fileURLWithPath: base + "-retranscribing.png"))
            dictation.retranscription = nil
        }
    }

    private static func render(_ model: AppModel, to url: URL) {
        let size = CGSize(width: 1180, height: 740)
        let host = NSHostingView(rootView: MainWindow().environment(model))
        host.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.contentView = nil
    }
}
