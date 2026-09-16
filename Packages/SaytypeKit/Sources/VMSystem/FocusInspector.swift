import AppKit
import ApplicationServices

/// Reads what the user is typing into, through the Accessibility API.
@MainActor
public enum FocusInspector {
    public static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    public static func frontmostAppName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    /// True when the focused element is a password field.
    public static func isSecureFieldFocused() -> Bool {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            return false
        }
        let element = focused as! AXUIElement
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success else {
            return false
        }
        return (subrole as? String) == (kAXSecureTextFieldSubrole as String)
    }
}
