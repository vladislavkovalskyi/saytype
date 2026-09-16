import Foundation

/// The app was called voicemode before it became saytype. On the first launch under the
/// new bundle id, models, history and settings move over so nothing downloads twice.
enum LegacyMigration {
    static let legacyID = "dev.kovalskyi.voicemode"
    static let settingsKey = "settings.v1"

    static func run(currentID: String = Bundle.main.bundleIdentifier ?? "dev.kovalskyi.saytype") {
        // Previews and snapshots must not move data out from under a running voicemode build.
        guard currentID != legacyID, !AppModel.isPreviewLaunch else { return }
        moveSupportFolder(to: currentID)
        copySettings()
    }

    private static func moveSupportFolder(to currentID: String) {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appending(path: legacyID, directoryHint: .isDirectory)
        let new = support.appending(path: currentID, directoryHint: .isDirectory)
        guard fileManager.fileExists(atPath: old.path), !fileManager.fileExists(atPath: new.path) else { return }
        try? fileManager.moveItem(at: old, to: new)
    }

    private static func copySettings() {
        let defaults = UserDefaults.standard
        guard defaults.data(forKey: settingsKey) == nil,
              let legacy = UserDefaults(suiteName: legacyID)?.data(forKey: settingsKey)
        else { return }
        defaults.set(legacy, forKey: settingsKey)
    }
}
