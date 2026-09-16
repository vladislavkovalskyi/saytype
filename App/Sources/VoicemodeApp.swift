import SwiftUI

@main
struct VoicemodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item is AppKit (StatusItemController); windows come from WindowManager.
        Settings { EmptyView() }
    }
}
