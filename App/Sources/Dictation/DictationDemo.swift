import AppKit
import VMCore

/// Plays the overlay through its states with sample text, for screenshots and
/// checking the design without permissions: `saytype --demo-overlay island`.
extension DictationController {
    func runDemo(style: AppSettings.OverlayStyle, settings: SettingsStore) {
        settings.value.overlayStyle = style
        let words = "поправь useEffect в Header, он дёргается при каждом рендере".split(separator: " ").map(String.init)
        let modes = settings.value.modes
        func mode(_ id: String) -> DictationMode { modes.first { $0.id == id } ?? DictationMode(id: id) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            // A mode with a language model: tag while recording, then the rewrite stage.
            demoMode(mode(DictationMode.commitID))
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
            try? await Task.sleep(for: .seconds(1))
            demoMode(mode(DictationMode.commitID), stage: .rewriting)
            try? await Task.sleep(for: .seconds(2))
            demoMode(mode(DictationMode.commitID))
            demoSet(phase: .inserted(TargetApp(name: "Terminal", bundleID: "com.apple.Terminal", icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app"))), committed: "", pending: "")
            try? await Task.sleep(for: .seconds(2))
            demoSet(phase: .notice(.mode(mode(DictationMode.promptID).title)), committed: "", pending: "")
            try? await Task.sleep(for: .seconds(1.4))
            demoSet(phase: .notice(.mode(mode(DictationMode.messageID).title)), committed: "", pending: "")
            try? await Task.sleep(for: .seconds(1.4))
            demoMode(mode(DictationMode.standardID))
            demoSet(phase: .card("Поправь useEffect в Header, он дёргается при каждом рендере."), committed: "", pending: "")
            try? await Task.sleep(for: .seconds(3))
            demoSet(phase: .notice(.passwordField), committed: "", pending: "")
            try? await Task.sleep(for: .seconds(2))
            demoSet(phase: .idle, committed: "", pending: "")
        }
    }
}

extension DictationController {
    /// In-memory history for `saytype --demo-menu`; nothing is written to disk.
    static func sampleHistory(now: Date = Date()) -> [DictationRecord] {
        let samples: [(String, String, String?, Double, Double)] = [
            ("Вынеси загрузку пользователя в хук useUser и добавь массив зависимостей.", "вынеси загрузку пользователя в хук юз юзер и добавь массив зависимостей", "Terminal", 6, 0),
            ("1. Поправь useEffect в Header.\n2. Задеплой feature/auth на Vercel.", "во-первых поправь юз эффект в хедер во-вторых задеплой фичер аус на версель", "Cursor", 9, 120),
            ("Задеплой feature/auth на Vercel и скинь превью.", "задеплой фичер аус на версель и скинь превью", "Cursor", 4, 2_640),
            ("Созвон перенесли на четыре, ссылку скину позже.", "созвон перенесли на четыре ссылку скину позже", "Telegram", 3, 4_260),
            ("Добавь в Supabase таблицу users с полями id, email и created_at.", "добавь в супабейс таблицу юзерс с полями айди имейл и криэйтед эт", "Cursor", 12, 6_900),
            ("localhost:3000/settings", "локалхост три тысячи слэш сеттингс", "Safari", 2, 9_000),
        ]
        var records = samples.enumerated().map { index, sample in
            let (text, raw, app, duration, ago) = sample
            let id = UUID()
            // The two newest keep their recordings, as with audio kept for a day.
            return DictationRecord(id: id, text: text, raw: raw, appName: app, bundleID: nil, duration: duration, date: now.addingTimeInterval(-ago), audio: index < 2 ? "\(id.uuidString).caf" : nil)
        }
        records[0].previous = DictationRecord.Version(text: "Вынеси загрузку пользователя в хук юз юзер.", raw: "вынеси загрузку пользователя в хук юз юзер")
        // A dictation the app lost to a crash, found on the next launch.
        let lost = UUID()
        records.insert(DictationRecord(id: lost, text: "", raw: "", appName: "Notes", bundleID: nil, duration: 94, date: now.addingTimeInterval(-1_800), audio: "\(lost.uuidString).caf", failure: .interrupted), at: 2)
        return records
    }
}
