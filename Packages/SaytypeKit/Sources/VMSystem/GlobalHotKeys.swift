import Carbon.HIToolbox
import Foundation
import VMCore

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

        public init(_ shortcut: KeyShortcut) {
            self.init(keyCode: shortcut.keyCode, control: shortcut.control, option: shortcut.option, command: shortcut.command, shift: shortcut.shift)
        }
    }

    private static let signature: OSType = 0x534B_4559 // "SKEY"
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    /// Ids keep growing, so a press queued for a removed shortcut can't reach its replacement.
    private var lastID: UInt32 = 0

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
        lastID += 1
        let id = lastID
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: Self.signature, id: id), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr, let reference else { return false }
        actions[id] = action
        references.append(reference)
        return true
    }

    /// Releases every shortcut, e.g. before registering the ones from changed settings.
    public func unregisterAll() {
        for reference in references {
            UnregisterEventHotKey(reference)
        }
        references = []
        actions = [:]
    }
}

// MARK: Names

extension KeyShortcut {
    /// Modifiers in the macOS order, then the key: ["⌃", "⌥", "V"].
    @MainActor
    public var symbols: [String] {
        var result: [String] = []
        if control { result.append("⌃") }
        if option { result.append("⌥") }
        if shift { result.append("⇧") }
        if command { result.append("⌘") }
        result.append(keyName)
        return result
    }

    /// "⌃⌥V"
    @MainActor
    public var displayName: String { symbols.joined() }

    /// F1…F20 work as shortcuts without modifiers.
    public var isFunctionKey: Bool { Self.functionKeys[keyCode] != nil }

    /// Global shortcuts need ⌃ or ⌥, or ⌘ with ⇧: a bare letter would stop typing it anywhere,
    /// and ⌘ alone belongs to app commands like ⌘C and ⌘V.
    public var isAllowed: Bool {
        isFunctionKey || control || option || (command && shift)
    }

    /// The key as printed on an ASCII-capable layout, so ⌃⌥V reads the same with a Russian layout on.
    @MainActor
    public var keyName: String {
        if let name = Self.functionKeys[keyCode] { return name }
        if let name = Self.specialKeys[keyCode] { return name }
        return Self.character(for: keyCode)?.uppercased() ?? "#\(keyCode)"
    }

    /// The character the key types on an ASCII-capable layout, for menu key equivalents.
    @MainActor
    public static func character(for keyCode: Int) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return OSStatus(paramErr) }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return nil }
        let character = String(utf16CodeUnits: characters, count: length)
        return character.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty ? nil : character
    }

    static let functionKeys: [Int: String] = [
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7",
        kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12", kVK_F13: "F13", kVK_F14: "F14",
        kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18", kVK_F19: "F19", kVK_F20: "F20",
    ]

    static let specialKeys: [Int: String] = [
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_Escape: "⎋", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
        kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_ANSI_KeypadEnter: "⌤", kVK_Help: "Help",
    ]
}
