import SwiftUI

@main
struct VoicemodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.model)
        } label: {
            MenuBarLabel(dictation: appDelegate.model.dictation)
        }
        .menuBarExtraStyle(.window)
    }
}

/// The menu bar icon fills while voicemode is listening or finishing a dictation.
private struct MenuBarLabel: View {
    let dictation: DictationController

    var body: some View {
        switch dictation.phase {
        case .listening, .finishing:
            Image(systemName: "waveform.circle.fill")
        default:
            Image(systemName: "waveform")
        }
    }
}
