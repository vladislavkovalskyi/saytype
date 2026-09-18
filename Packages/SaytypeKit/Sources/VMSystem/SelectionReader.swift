import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Reads the text the user has selected in the app in front, for a dictation that edits it
/// instead of adding to it.
///
/// Two ways, in this order: the Accessibility API, which reads the selection without touching
/// anything, and — for apps that do not answer, such as terminals and many Electron apps — a
/// ⌘C with the clipboard put back afterwards.
@MainActor
public enum SelectionReader {
    /// Past this many characters a local model runs longer than its time limit.
    public static let limit = 6000

    /// The selected text, or `nil` when nothing is selected or it cannot be read.
    public static func read() async -> String? {
        guard !FocusInspector.isSecureFieldFocused(), !IsSecureEventInputEnabled() else { return nil }
        if let text = accessibilitySelection() { return text }
        return await copiedSelection()
    }

    private static func accessibilitySelection() -> String? {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            return nil
        }
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected) == .success
        else {
            return nil
        }
        return usable(selected as? String)
    }

    /// The clipboard's change count says whether anything was copied: an app with nothing
    /// selected leaves the clipboard alone, and then the old contents are never touched.
    private static func copiedSelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard)
        let before = pasteboard.changeCount
        KeyPoster.press(KeyPoster.keycode(for: "c", fallback: CGKeyCode(kVK_ANSI_C)), flags: .maskCommand)
        for _ in 0..<20 {
            try? await Task.sleep(for: .milliseconds(20))
            guard pasteboard.changeCount != before else { continue }
            let text = usable(pasteboard.string(forType: .string))
            snapshot.restore(to: pasteboard)
            return text
        }
        return nil
    }

    private static func usable(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return String(text.prefix(limit))
    }
}
