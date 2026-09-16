import Carbon.HIToolbox
import Foundation

/// System-wide shortcuts through Carbon hot keys. They need no permission and work in
/// any app; the key code is the physical key, so ⌃⌥V is the same key on every layout.
@MainActor
public final class GlobalHotKeys {
    public struct Shortcut: Hashable, Sendable {
        public let keyCode: UInt32
        public let modifiers: UInt32

        public init(keyCode: Int, control: Bool = false, option: Bool = false, command: Bool = false, shift: Bool = false) {
            self.keyCode = UInt32(keyCode)
            var flags = 0
            if control { flags |= controlKey }
            if option { flags |= optionKey }
            if command { flags |= cmdKey }
            if shift { flags |= shiftKey }
            modifiers = UInt32(flags)
        }

        public static let pasteAgain = Shortcut(keyCode: kVK_ANSI_V, control: true, option: true)
        public static let copyLast = Shortcut(keyCode: kVK_ANSI_C, control: true, option: true)
    }

    private static let signature: OSType = 0x534B_4559 // "SKEY"
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    public init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(context).takeUnretainedValue()
            // Carbon delivers hot key events on the main thread.
            MainActor.assumeIsolated { hotKeys.actions[id.id]?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    /// Returns false when another app already owns the shortcut.
    @discardableResult
    public func register(_ shortcut: Shortcut, action: @escaping @MainActor () -> Void) -> Bool {
        let id = UInt32(actions.count + 1)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        actions[id] = action
        references.append(reference)
        return true
    }
}
