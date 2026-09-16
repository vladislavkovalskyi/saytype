import Foundation
import Observation
import VMCore

/// Keeps `AppSettings` in UserDefaults as one JSON document.
@MainActor
@Observable
final class SettingsStore {
    private static let key = "settings.v1"
    private let defaults: UserDefaults
    /// Demo and preview launches (`--demo-overlay`, `--show-main`, …) neither read nor write the
    /// user's settings: the dictionary and preferences stay private in screenshots.
    private let persists = !AppModel.isPreviewLaunch

    var value: AppSettings {
        didSet {
            guard persists, value != oldValue, let data = try? JSONEncoder().encode(value) else { return }
            defaults.set(data, forKey: Self.key)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if persists, let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = stored
        } else {
            value = AppSettings()
        }
    }
}
