import AppKit
import ApplicationServices
import AVFoundation
import CoreGraphics

/// The three macOS privacy permissions saytype needs.
public enum Permission: String, CaseIterable, Sendable {
    /// Hearing the user.
    case microphone
    /// Posting ⌘V into the focused app and reading the focused element.
    case accessibility
    /// Listening to fn from any app.
    case inputMonitoring
}

public enum PermissionState: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
}

public enum Permissions {
    public static func state(of permission: Permission) -> PermissionState {
        switch permission {
        case .microphone:
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .denied: return .denied
            default: return .notDetermined
            }
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .inputMonitoring:
            return CGPreflightListenEventAccess() ? .granted : .notDetermined
        }
    }

    /// Shows the system prompt where macOS has one. Accessibility and Input
    /// Monitoring only register the app in System Settings; the user flips the switch there.
    public static func request(_ permission: Permission) async -> PermissionState {
        switch permission {
        case .microphone:
            let granted = await AVAudioApplication.requestRecordPermission()
            return granted ? .granted : .denied
        case .accessibility:
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options) ? .granted : .notDetermined
        case .inputMonitoring:
            return CGRequestListenEventAccess() ? .granted : .notDetermined
        }
    }

    @MainActor
    public static func openSystemSettings(for permission: Permission) {
        let anchor = switch permission {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .inputMonitoring: "Privacy_ListenEvent"
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
