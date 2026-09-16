import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
            Fonts.register()
            model.start()
        }
    }

    /// Opening the app again from Finder or Spotlight shows a window: the user
    /// may have hidden the menu bar icon.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            if model.settings.value.onboardingCompleted {
                model.windows.showMain()
            } else {
                model.windows.showOnboarding()
            }
        }
        return true
    }
}
