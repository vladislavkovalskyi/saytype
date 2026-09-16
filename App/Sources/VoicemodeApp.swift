import SwiftUI

@main
struct VoicemodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.model)
        } label: {
            Image(systemName: "waveform")
        }
        .menuBarExtraStyle(.window)
    }
}
