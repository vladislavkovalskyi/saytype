import AppKit
import Observation
import VMCore
import VMSystem

/// Root state shared by every window.
@MainActor
@Observable
final class AppModel {
    let settings = SettingsStore()
    @ObservationIgnored private(set) lazy var windows = WindowManager(model: self)
    private(set) var permissions: [Permission: PermissionState] = [:]

    @ObservationIgnored private var permissionTimer: Timer?

    func start() {
        refreshPermissions()
        // macOS has no callback for Accessibility and Input Monitoring changes.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
        if !settings.value.onboardingCompleted {
            windows.showOnboarding()
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
