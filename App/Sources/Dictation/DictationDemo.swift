import Foundation
import VMCore

/// Plays the overlay through its states with sample text, for screenshots and
/// checking the design without permissions: `voicemode --demo-overlay island`.
extension DictationController {
    func runDemo(style: AppSettings.OverlayStyle, settings: SettingsStore) {
        settings.value.overlayStyle = style
        let words = "поправь useEffect в Header, он дёргается при каждом рендере".split(separator: " ").map(String.init)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            demoSet(phase: .listening, committed: "", pending: "")
            for i in 1...words.count {
                try? await Task.sleep(for: .milliseconds(450))
                demoLevels()
                let committed = words.prefix(max(0, i - 2)).joined(separator: " ")
                let pending = words.dropFirst(max(0, i - 2)).prefix(2).joined(separator: " ")
                demoSet(phase: .listening, committed: committed, pending: pending)
            }
            try? await Task.sleep(for: .seconds(1.5))
            demoSet(phase: .finishing, committed: words.joined(separator: " "), pending: "")
            try? await Task.sleep(for: .seconds(1.5))
            demoSet(phase: .inserted(appName: "Терминал"), committed: "", pending: "")
            try? await Task.sleep(for: .seconds(2))
            demoSet(phase: .card("Поправь useEffect в Header, он дёргается при каждом рендере."), committed: "", pending: "")
            try? await Task.sleep(for: .seconds(3))
            demoSet(phase: .notice("Поле пароля"), committed: "", pending: "")
            try? await Task.sleep(for: .seconds(2))
            demoSet(phase: .idle, committed: "", pending: "")
        }
    }
}
