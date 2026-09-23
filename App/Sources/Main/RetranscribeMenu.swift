import Foundation
import VMCore

/// The ways to transcribe a kept recording again, for the History section and the card: as is,
/// with another Whisper model on disk, in another language, or without translation.
@MainActor
enum RetranscribeMenu {
    static func items(for record: DictationRecord, dictation: DictationController) -> [MenuOption] {
        let value = dictation.settings.value
        let id = record.id
        let models = dictation.downloadedModels
        let current = value.whisperModel
        let again = record.isTranscribed
            ? String(localized: "Transcribe Again", comment: "Menu with the ways to transcribe a kept recording again")
            : String(localized: "Transcribe", comment: "Menu that transcribes a recording that has no text yet")

        let modelItems = models.map { variant in
            MenuOption(title: DictationController.modelTitle(variant, among: models), isOn: variant == current) {
                dictation.retranscribe(id, variant == current ? .none : .model(variant))
            }
        }
        var languageItems: [MenuOption] = []
        for (index, language) in AppSettings.SpeechLanguage.all().enumerated() {
            // Russian, English and Automatic, then the rest, as in the menu bar.
            if index == 3 { languageItems.append(.separator) }
            let title = switch language {
            case .russian: "Русский"
            case .english: "English"
            case .auto: String(localized: "Automatic")
            default: language.localizedName()
            }
            languageItems.append(MenuOption(title: title, isOn: language == value.language) {
                dictation.retranscribe(id, language == value.language ? .none : .language(language))
            })
        }

        return [
            MenuOption(title: again, isOn: false, action: { dictation.retranscribe(id) }, isEnabled: dictation.modelState == .ready),
            .separator,
            .submenu(String(localized: "Model"), modelItems),
            .submenu(String(localized: "Language"), languageItems),
            MenuOption(
                title: String(localized: "Without Translation", comment: "Re-transcription menu: the same recording, left in the spoken language"),
                isOn: false,
                action: { dictation.retranscribe(id, .withoutTranslation) },
                isEnabled: dictation.wouldTranslate(record)
            ),
        ]
    }
}
