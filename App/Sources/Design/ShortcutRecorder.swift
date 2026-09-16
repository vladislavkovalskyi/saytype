import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI
import VMCore
import VMSystem

/// A global shortcut as key caps. Click, then press the keys: esc cancels, delete turns the
/// shortcut off. While it listens, the app's global shortcuts step aside.
struct ShortcutRecorder: View {
    @Environment(AppModel.self) private var model
    @Binding var shortcut: KeyShortcut?
    /// Shortcuts of the other actions; pressing one of them is refused.
    var others: [KeyShortcut] = []
    @Binding var isRecording: Bool
    @State private var recorder = KeyRecorder()

    var body: some View {
        Button(action: toggle) {
            label
                .frame(minWidth: 96, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onChange(of: recorder.isRecording) { _, recording in
            isRecording = recording
        }
        .onDisappear { recorder.stop() }
        .animation(.snappy(duration: 0.18), value: recorder.isRecording)
    }

    @ViewBuilder
    private var label: some View {
        if recorder.isRecording {
            Text(recordingTitle)
                .font(.onest(13, .medium))
                .foregroundStyle(.white.opacity(recorder.problem == nil && recorder.held.isEmpty ? 0.8 : 1))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(Capsule().fill(.white.opacity(0.14)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1.5))
                .fixedSize()
        } else if let shortcut {
            HStack(spacing: 4) {
                ForEach(Array(shortcut.symbols.enumerated()), id: \.offset) { _, symbol in
                    Keycap(symbol)
                }
            }
        } else {
            Text("Off")
                .font(.onest(13, .medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(ChipFill())
                .fixedSize()
        }
    }

    private var recordingTitle: String {
        switch recorder.problem {
        case .needsModifier: String(localized: "Add ⌃ or ⌥", comment: "A shortcut without modifiers was pressed in the shortcut recorder")
        case .inUse: String(localized: "In use", comment: "The pressed shortcut already belongs to another action")
        case nil: recorder.held.isEmpty ? String(localized: "Press keys", comment: "Shortcut recorder waiting for a key press") : recorder.held.joined()
        }
    }

    private func toggle() {
        guard !recorder.isRecording else {
            recorder.stop()
            return
        }
        let others = others
        recorder.start(model: model) { candidate in
            if !candidate.isAllowed { return .needsModifier }
            if others.contains(candidate) { return .inUse }
            return nil
        } finish: { outcome in
            switch outcome {
            case .set(let value): shortcut = value
            case .clear: shortcut = nil
            case .cancel: break
            }
        }
    }
}

/// Listens to key presses in this app for one shortcut recorder at a time.
@MainActor
@Observable
final class KeyRecorder {
    enum Problem: Equatable {
        case needsModifier
        case inUse
    }

    enum Outcome {
        case set(KeyShortcut)
        case clear
        case cancel
    }

    private(set) var isRecording = false
    /// Modifiers held down so far: ["⌃", "⌥"].
    private(set) var held: [String] = []
    private(set) var problem: Problem?

    @ObservationIgnored private weak var model: AppModel?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var resignObserver: NSObjectProtocol?
    @ObservationIgnored private var validate: (KeyShortcut) -> Problem? = { _ in nil }
    @ObservationIgnored private var finish: (Outcome) -> Void = { _ in }
    @ObservationIgnored private var problemTask: Task<Void, Never>?
    /// Starting a second recorder stops the first.
    @ObservationIgnored private static weak var active: KeyRecorder?

    func start(model: AppModel, validate: @escaping (KeyShortcut) -> Problem?, finish: @escaping (Outcome) -> Void) {
        Self.active?.stop()
        Self.active = self
        self.model = model
        model.setRecordingShortcut(true)
        self.validate = validate
        self.finish = finish
        held = []
        problem = nil
        isRecording = true
        // Previews draw the listening state but never take the keyboard.
        guard !AppModel.isPreviewLaunch else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let type = event.type
            let keyCode = Int(event.keyCode)
            let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
            // Local monitors run on the main thread.
            let swallow = MainActor.assumeIsolated { self?.handle(type: type, keyCode: keyCode, flags: flags) ?? false }
            return swallow ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        problemTask?.cancel()
        if Self.active === self { Self.active = nil }
        guard isRecording else { return }
        isRecording = false
        held = []
        problem = nil
        model?.setRecordingShortcut(false)
    }

    private func handle(type: NSEvent.EventType, keyCode: Int, flags: NSEvent.ModifierFlags) -> Bool {
        if type == .flagsChanged {
            held = Self.symbols(flags)
            return false
        }
        if flags.isEmpty, keyCode == kVK_Escape {
            complete(.cancel)
            return true
        }
        if flags.isEmpty, keyCode == kVK_Delete || keyCode == kVK_ForwardDelete {
            complete(.clear)
            return true
        }
        let shortcut = KeyShortcut(keyCode: keyCode, control: flags.contains(.control), option: flags.contains(.option), command: flags.contains(.command), shift: flags.contains(.shift))
        if let problem = validate(shortcut) {
            show(problem)
        } else {
            complete(.set(shortcut))
        }
        // Keys pressed while listening never reach the window.
        return true
    }

    private func complete(_ outcome: Outcome) {
        let finish = finish
        stop()
        finish(outcome)
    }

    private func show(_ problem: Problem) {
        self.problem = problem
        problemTask?.cancel()
        problemTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            self?.problem = nil
        }
    }

    private static func symbols(_ flags: NSEvent.ModifierFlags) -> [String] {
        var result: [String] = []
        if flags.contains(.control) { result.append("⌃") }
        if flags.contains(.option) { result.append("⌥") }
        if flags.contains(.shift) { result.append("⇧") }
        if flags.contains(.command) { result.append("⌘") }
        return result
    }
}

// MARK: Menus

extension NSMenuItem {
    /// Shows a global shortcut next to the item; nothing when the shortcut is off.
    @MainActor
    func showShortcut(_ shortcut: KeyShortcut?) {
        guard let shortcut, let key = shortcut.menuKeyEquivalent else {
            keyEquivalent = ""
            keyEquivalentModifierMask = []
            return
        }
        keyEquivalent = key
        var mask: NSEvent.ModifierFlags = []
        if shortcut.control { mask.insert(.control) }
        if shortcut.option { mask.insert(.option) }
        if shortcut.shift { mask.insert(.shift) }
        if shortcut.command { mask.insert(.command) }
        keyEquivalentModifierMask = mask
    }
}

extension KeyShortcut {
    /// The character AppKit expects as a key equivalent: "v", a function key's private-use character, "\r".
    @MainActor
    var menuKeyEquivalent: String? {
        if isFunctionKey, let number = Int(keyName.dropFirst()) {
            return UnicodeScalar(UInt32(NSF1FunctionKey + number - 1)).map { String(Character($0)) }
        }
        let special: [Int: Int] = [
            kVK_Return: 0x0D, kVK_ANSI_KeypadEnter: 0x03, kVK_Tab: 0x09, kVK_Space: 0x20, kVK_Delete: 0x08, kVK_Escape: 0x1B,
            kVK_ForwardDelete: NSDeleteFunctionKey, kVK_LeftArrow: NSLeftArrowFunctionKey, kVK_RightArrow: NSRightArrowFunctionKey,
            kVK_UpArrow: NSUpArrowFunctionKey, kVK_DownArrow: NSDownArrowFunctionKey, kVK_Home: NSHomeFunctionKey,
            kVK_End: NSEndFunctionKey, kVK_PageUp: NSPageUpFunctionKey, kVK_PageDown: NSPageDownFunctionKey, kVK_Help: NSHelpFunctionKey,
        ]
        if let code = special[keyCode] {
            return UnicodeScalar(UInt32(code)).map { String(Character($0)) }
        }
        return Self.character(for: keyCode)?.lowercased()
    }
}
