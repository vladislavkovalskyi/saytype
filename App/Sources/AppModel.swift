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
    private(set) var permissions: [Permission: PermissionState] = [:]
    /// Section shown in the main window.
    var mainSection = MainSection.home

    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var monitoredKey: AppSettings.RecordKey?

    func start() {
        refreshPermissions()
        overlay = OverlayController(dictation: dictation, settings: settings)
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
        if arguments.contains("--demo-menu") {
            Task {
                // Lands after activate() has read the real history.
                try? await Task.sleep(for: .milliseconds(500))
                dictation.demoHistory(DictationController.sampleHistory())
            }
            windows.showMenuPreview()
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
    static let isPreviewLaunch = ProcessInfo.processInfo.arguments.contains { $0.hasPrefix("--demo") || $0.hasPrefix("--show") }

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
            next[permission] = Permissions.state(of: permission)
        }
        if next != permissions {
            permissions = next
        }
    }

    func state(of permission: Permission) -> PermissionState {
        permissions[permission] ?? .notDetermined
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
