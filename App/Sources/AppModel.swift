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
    /// The shortcuts registered now; `nil` while a shortcut recorder listens.
    @ObservationIgnored private var registeredShortcuts: AppSettings.Shortcuts?
    /// Shortcuts that failed to register because another app holds them.
    private(set) var takenShortcuts: Set<ShortcutAction> = []
    /// A shortcut recorder is listening; global shortcuts step aside so it gets their keys.
    private(set) var isRecordingShortcut = false
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
        hotKeys = GlobalHotKeys()
        updateHotKeys()
        observeShortcuts()
    }

    /// Registers the shortcuts again whenever they change in settings.
    private func observeShortcuts() {
        withObservationTracking {
            _ = settings.value.shortcuts
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.updateHotKeys()
                self?.observeShortcuts()
            }
        }
    }

    private func updateHotKeys() {
        guard let keys = hotKeys else { return }
        let wanted = isRecordingShortcut ? nil : settings.value.shortcuts
        guard wanted != registeredShortcuts else { return }
        keys.unregisterAll()
        registeredShortcuts = wanted
        guard let wanted else { return }
        var taken: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases {
            guard let shortcut = wanted[keyPath: action.keyPath] else { continue }
            if !keys.register(GlobalHotKeys.Shortcut(shortcut), action: perform(action)) {
                taken.insert(action)
            }
        }
        if taken != takenShortcuts { takenShortcuts = taken }
    }

    private func perform(_ action: ShortcutAction) -> @MainActor () -> Void {
        let dictation = dictation
        switch action {
        case .pasteAgain:
            return { if let last = dictation.lastRecord { dictation.insertAgain(last) } }
        case .copyLast:
            return { if let last = dictation.lastRecord { Paster.copy(last.text) } }
        case .cycleMode:
            return { dictation.cycleMode() }
        }
    }

    /// Called by a shortcut recorder when it starts and stops listening.
    func setRecordingShortcut(_ recording: Bool) {
        guard recording != isRecordingShortcut else { return }
        isRecordingShortcut = recording
        updateHotKeys()
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

/// What a global shortcut does.
enum ShortcutAction: CaseIterable, Hashable {
    case pasteAgain
    case copyLast
    case cycleMode

    var keyPath: WritableKeyPath<AppSettings.Shortcuts, KeyShortcut?> {
        switch self {
        case .pasteAgain: \.pasteAgain
        case .copyLast: \.copyLast
        case .cycleMode: \.cycleMode
        }
    }
}
