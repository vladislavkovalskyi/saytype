import Foundation
import Testing
@testable import VMCore

@Suite struct AppSettingsTests {
    @Test func roundTripsThroughJSON() throws {
        var settings = AppSettings()
        settings.overlayStyle = .pill
        settings.fillerMode = .all
        settings.autoEnterApps = ["com.mitchellh.ghostty"]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(AppSettings.self, from: data) == settings)
    }

    @Test func missingFieldsFallBackToDefaults() throws {
        let partial = Data(#"{"overlayStyle":"pill","language":"en"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: partial)
        #expect(settings.overlayStyle == .pill)
        #expect(settings.language == .english)
        #expect(settings.recordKey == .fn)
        #expect(settings.whisperModel == AppSettings().whisperModel)
    }

    @Test func storedLanguageWinsOverSystemDefault() throws {
        for language in [AppSettings.SpeechLanguage.russian, .english, .auto, .init(rawValue: "pl")] {
            let document = Data(#"{"language":"\#(language.rawValue)"}"#.utf8)
            #expect(try JSONDecoder().decode(AppSettings.self, from: document).language == language)
        }
    }

    @Test func missingLanguageFallsBackToSystemDefault() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(settings.language == AppSettings.SpeechLanguage.systemDefault)
        #expect(AppSettings().language == AppSettings.SpeechLanguage.systemDefault)
    }

    @Test(arguments: [
        (["ru-RU", "en-US"], AppSettings.SpeechLanguage.russian),
        (["ru"], .russian),
        (["en-GB", "ru-RU"], .english),
        (["en"], .english),
        (["de-DE", "ru-RU"], .init(rawValue: "de")),
        (["uk-UA"], .init(rawValue: "uk")),
        (["zh-Hans-CN"], .init(rawValue: "zh")),
        (["nb-NO"], .init(rawValue: "no")),
        (["tlh"], .auto),
        ([], .auto),
    ])
    func defaultLanguageFollowsPrimarySystemLanguage(preferred: [String], expected: AppSettings.SpeechLanguage) {
        #expect(AppSettings.SpeechLanguage.matching(preferredLanguages: preferred) == expected)
    }

    @Test func languageListStartsWithRussianEnglishAuto() {
        let all = AppSettings.SpeechLanguage.all(locale: Locale(identifier: "en_US"))
        #expect(Array(all.prefix(3)) == [.russian, .english, .auto])
        #expect(all.count == AppSettings.SpeechLanguage.whisperCodes.count + 1)
        #expect(AppSettings.SpeechLanguage(rawValue: "pl").localizedName(locale: Locale(identifier: "en_US")) == "Polish")
        #expect(AppSettings.SpeechLanguage.auto.whisperCode == nil)
    }
}
