import Foundation
import Testing
@testable import VMCore

@Suite struct ModesTests {
    @Test func modeFollowsTheFocusedApp() {
        let settings = AppSettings()
        #expect(settings.mode(for: "ru.keepcoder.Telegram").id == DictationMode.messageID)
        #expect(settings.mode(for: "com.apple.Terminal").id == DictationMode.promptID)
        #expect(settings.mode(for: "com.apple.Safari").isStandard)
        #expect(settings.mode(for: nil).isStandard)
    }

    @Test func fixedModeWinsOverTheApp() {
        var settings = AppSettings()
        settings.fixedModeID = DictationMode.commitID
        #expect(settings.mode(for: "ru.keepcoder.Telegram").id == DictationMode.commitID)
        settings.fixedModeID = "deleted"
        #expect(settings.mode(for: "ru.keepcoder.Telegram").id == DictationMode.messageID)
    }

    @Test func cycleGoesThroughEveryModeAndBackToAutomatic() {
        var settings = AppSettings()
        var seen: [String?] = []
        for _ in 0...settings.modes.count {
            settings.cycleMode()
            seen.append(settings.fixedModeID)
        }
        #expect(seen == settings.modes.map(\.id) + [nil])
    }

    @Test func modeStyleReplacesTheTextSection() {
        var settings = AppSettings()
        settings.letterCase = .asSpoken
        let message = settings.mode(for: "ru.keepcoder.Telegram")
        let applied = settings.applying(message)
        #expect(applied.isChatStyle)
        #expect(applied.smartStructure == false)
        #expect(settings.applying(settings.standardMode) == settings)
    }

    @Test func oldSettingsGetDefaultModesAndShortcuts() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"punctuation":true}"#.utf8))
        #expect(settings.modes == DictationMode.defaults)
        #expect(settings.shortcuts.cycleMode == .cycleMode)
        #expect(settings.languageModel.engine == .off)
    }

    @Test func turnedOffShortcutStaysOff() throws {
        var settings = AppSettings()
        settings.shortcuts.copyLast = nil
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(decoded.shortcuts.copyLast == nil)
        #expect(decoded.shortcuts.pasteAgain == .pasteAgain)
        #expect(decoded == settings)
    }

    @Test func standardModeIsRestoredWhenMissing() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"modes":[{"id":"x","name":"Bug report"}]}"#.utf8))
        #expect(settings.modes.first?.isStandard == true)
        #expect(settings.modes.last?.name == "Bug report")
    }

    @Test func pipelineWithoutCommandsMatchesTheFormatter() {
        let settings = AppSettings()
        let transcript = Transcript(text: "эээ поправь юз эффект в хедере")
        let result = DictationPipeline.format(transcript, settings: settings, mode: settings.standardMode)
        #expect(result.text == TextFormatter.format(transcript, settings: settings))
        #expect(result.send == false)
    }
}
