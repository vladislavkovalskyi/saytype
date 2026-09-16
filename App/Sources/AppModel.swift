import AppKit
import SwiftUI
import Observation
import VMCore
import VMSystem

/// Root state shared by every window.
@MainActor
@Observable
final class AppModel {
    let settings = SettingsStore()
    @ObservationIgnored private(set) lazy var dictation = DictationController(settings: settings)
    @ObservationIgnored private(set) lazy var windows = WindowManager(model: self)
    @ObservationIgnored private var overlay: OverlayController?
    @ObservationIgnored private var statusItem: StatusItemController?
    @ObservationIgnored private var hotKeys: GlobalHotKeys?
    /// Sparkle; stays off in preview launches and in builds without a signing key.
    @ObservationIgnored private(set) var updater: Updater?
    private(set) var permissions: [Permission: PermissionState] = [:]
    /// Section shown in the main window.
    var mainSection = MainSection.home

    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var monitoredKey: AppSettings.RecordKey?

    func start() {
        let launchArguments = ProcessInfo.processInfo.arguments
        if let i = launchArguments.firstIndex(of: "--snapshot-overlays"), i + 1 < launchArguments.count {
            OverlaySnapshots.run(into: URL(fileURLWithPath: launchArguments[i + 1]), model: self)
            exit(0)
        }
        refreshPermissions()
        let overlayModel = OverlayModel(
            dictation: dictation,
            settings: settings,
            openMain: { [weak self] section in
                self?.mainSection = section
                self?.windows.showMain()
            },
            smartStructure: smartStructureBinding
        )
        // Window previews don't need an island competing with the real app at the notch.
        if !Self.isPreviewLaunch || ProcessInfo.processInfo.arguments.contains("--demo-overlay") {
            overlay = OverlayController(model: overlayModel)
        }
        if !Self.isPreviewLaunch {
            updater = Updater()
            statusItem = StatusItemController(model: self)
            registerHotKeys()
        }
        dictation.activate(listening: !Self.isPreviewLaunch)
        monitoredKey = settings.value.recordKey
        // macOS has no callback for Accessibility and Input Monitoring changes.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--demo-overlay"), i + 1 < arguments.count,
           let style = AppSettings.OverlayStyle(rawValue: arguments[i + 1]) {
            dictation.runDemo(style: style, settings: settings)
            return
        }
        if let i = arguments.firstIndex(of: "--show-main"), i + 1 < arguments.count,
           let section = MainSection(rawValue: arguments[i + 1]) {
            mainSection = section
            windows.showMain()
            return
        }
        if !settings.value.onboardingCompleted || OnboardingFlow.launchStep != nil {
            windows.showOnboarding()
        }
    }

    /// `--demo-*` and `--show-*` launches only draw the UI. They never take the record key,
    /// so a preview next to the real app cannot record or paste a second time.
    nonisolated static let isPreviewLaunch = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--demo") || $0.hasPrefix("--show") || $0.hasPrefix("--snapshot") }

    private func tick() {
        guard !Self.isPreviewLaunch else { return }
        let hadInputMonitoring = state(of: .inputMonitoring) == .granted
        refreshPermissions()
        let hasInputMonitoring = state(of: .inputMonitoring) == .granted
        let keyChanged = monitoredKey != settings.value.recordKey
        if (hasInputMonitoring && !hadInputMonitoring) || (hasInputMonitoring && !dictation.keyMonitorActive) || keyChanged {
            monitoredKey = settings.value.recordKey
            dictation.startKeyMonitor()
        }
    }

    func refreshPermissions() {
        var next: [Permission: PermissionState] = [:]
        for permission in Permission.allCases {
            // Previews show a set-up app and never reveal this Mac's real permission state.
            next[permission] = Self.isPreviewLaunch ? .granted : Permissions.state(of: permission)
        }
        if next != permissions {
            permissions = next
        }
    }

    func state(of permission: Permission) -> PermissionState {
        permissions[permission] ?? .notDetermined
    }

    private func registerHotKeys() {
        let keys = GlobalHotKeys()
        let dictation = dictation
        keys.register(.pasteAgain) {
            if let last = dictation.lastRecord { dictation.insertAgain(last) }
        }
        keys.register(.copyLast) {
            if let last = dictation.lastRecord { Paster.copy(last.text) }
        }
        hotKeys = keys
    }

    /// Settings switch for smart structure; turning it on downloads the model.
    var smartStructureBinding: Binding<Bool> {
        let smart = dictation.smart
        return Binding { smart.isOn(self.settings.value) } set: { smart.turn($0, settings: self.settings) }
    }

    func finishOnboarding() {
        settings.value.onboardingCompleted = true
        windows.closeOnboarding()
    }
}
