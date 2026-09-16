import AppKit
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

    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var monitoredKey: AppSettings.RecordKey?

    func start() {
        refreshPermissions()
        overlay = OverlayController(dictation: dictation, settings: settings)
        dictation.activate()
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
        if !settings.value.onboardingCompleted || OnboardingFlow.launchStep != nil {
            windows.showOnboarding()
        }
    }

    private func tick() {
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

    func finishOnboarding() {
        settings.value.onboardingCompleted = true
        windows.closeOnboarding()
    }
}
