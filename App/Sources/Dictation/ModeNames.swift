import Foundation
import VMCore

extension DictationMode {
    /// Name in the interface language; custom modes keep the name the user gave them.
    var title: String {
        switch id {
        case Self.standardID: String(localized: "Standard", comment: "Dictation mode: the rules from the Text section")
        case Self.messageID: String(localized: "Message", comment: "Dictation mode for messengers")
        case Self.promptID: String(localized: "Agent prompt", comment: "Dictation mode for coding agents and terminals")
        case Self.commitID: String(localized: "Commit", comment: "Dictation mode that writes a commit message")
        case Self.emailID: String(localized: "Email", comment: "Dictation mode for email")
        default: name.isEmpty ? String(localized: "Untitled mode") : name
        }
    }

    /// Automatic selection by the focused app, in the mode menu and the mode notice.
    static var automaticTitle: String {
        String(localized: "Mode by app", comment: "Dictation mode picked by the focused app")
    }
}
