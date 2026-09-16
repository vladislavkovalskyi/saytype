import Foundation
import Observation
import os
import Sparkle

/// Sparkle 2 updater. Create one at launch and keep it for the life of the app; the menu calls
/// `checkForUpdates()` and disables its item while `canCheckForUpdates` is false.
///
/// Sparkle starts only when Info.plist carries a real `SUPublicEDKey`. With the placeholder key
/// `SPUUpdater` refuses to start and `SPUStandardUpdaterController` shows a modal
/// "Unable to Check For Updates" alert a second after launch, so such builds keep the updater
/// stopped. Preview launches (`--show-*`, `--demo-*`) never start it either.
@MainActor
@Observable
final class Updater {
    /// Sparkle is running and no update session is in progress.
    private(set) var canCheckForUpdates = false

    /// False when the build has no valid EdDSA public key or this is a preview launch.
    let isEnabled: Bool

    @ObservationIgnored private let controller: SPUStandardUpdaterController
    @ObservationIgnored private var observation: NSKeyValueObservation?

    private static let log = Logger(subsystem: "dev.kovalskyi.voicemode", category: "updates")

    init(bundle: Bundle = .main) {
        let hasKey = Self.hasValidPublicKey(in: bundle)
        isEnabled = hasKey && !AppModel.isPreviewLaunch
        controller = SPUStandardUpdaterController(
            startingUpdater: isEnabled,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        guard isEnabled else {
            if !hasKey {
                Self.log.notice("Updates off: SUPublicEDKey is not a valid EdDSA public key")
            }
            return
        }
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
            MainActor.assumeIsolated {
                self?.canCheckForUpdates = updater.canCheckForUpdates
            }
        }
    }

    /// Shows Sparkle's standard update window and checks the feed now.
    func checkForUpdates() {
        guard isEnabled else { return }
        controller.checkForUpdates(nil)
    }

    /// Sparkle's own rule: the key is base64 for 32 bytes.
    static func hasValidPublicKey(in bundle: Bundle) -> Bool {
        guard let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              let data = Data(base64Encoded: key.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return false }
        return data.count == 32
    }
}
