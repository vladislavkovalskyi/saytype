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
}
