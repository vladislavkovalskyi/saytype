import AppKit
import VMCore
import VMSystem

// Checks what the screen context reader gets from an app, and how fast.
//
//   vm-context <pid | app name> --marker <text> [--runs n] [--text] [--budget ms]
//
// It reads only a window whose title contains the marker, so a test window opened for the check
// is read and no other window ever is: the app's focused window is checked before and after the
// read, and nothing is printed when the title does not carry the marker. Needs the Accessibility
// permission for the terminal it runs in.

let arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count else { return nil }
    return arguments[i + 1]
}

guard let target = arguments.first, !target.hasPrefix("--"), let marker = option("--marker"), !marker.isEmpty else {
    print("usage: vm-context <pid | app name> --marker <text in the window title> [--runs n] [--text] [--budget ms]")
    exit(2)
}
guard AXIsProcessTrusted() else {
    print("no Accessibility permission for this process")
    exit(1)
}
let app = pid_t(target).flatMap { NSRunningApplication(processIdentifier: $0) }
    ?? NSWorkspace.shared.runningApplications.first { $0.localizedName == target || $0.bundleIdentifier == target }
guard let app else {
    print("no running app \(target)")
    exit(1)
}

/// The focused window's title carries the marker; any other title is neither read nor printed.
func focusedWindowIsMarked() -> Bool {
    let element = AXUIElementCreateApplication(app.processIdentifier)
    var window: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success, let window else { return false }
    var title: CFTypeRef?
    guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success else { return false }
    return (title as? String)?.contains(marker) == true
}

func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}

var limits = ScreenContextReader.Limits()
if let budget = option("--budget").flatMap(Int.init) { limits.budget = .milliseconds(budget) }
let runs = option("--runs").flatMap(Int.init) ?? 3
print("\(app.localizedName ?? "?") [\(app.bundleIdentifier ?? "")] pid \(app.processIdentifier)")
for run in 1...runs {
    guard focusedWindowIsMarked() else {
        print("the focused window's title has no \"\(marker)\"; nothing read")
        exit(1)
    }
    let reading = ScreenContextReader.read(pid: app.processIdentifier, limits: limits)
    guard reading.text.title.contains(marker) else {
        print("the window changed during the read; nothing printed")
        exit(1)
    }
    let terms = ScreenTerms.extract(from: reading.text)
    let visible = reading.text.visible.reduce(0) { $0 + $1.count }
    print(String(format: "run %d: %.1f ms, %d nodes%@, title %d, focused %d (%@), visible %d chars in %d pieces%@",
                 run, milliseconds(reading.elapsed), reading.nodes, reading.truncated ? " (cut short)" : "",
                 reading.text.title.count, reading.text.focused.count, reading.focusedRole ?? "none",
                 visible, reading.text.visible.count, reading.webText ? ", web text" : ""))
    if run == runs {
        print("terms (\(terms.count)): " + terms.joined(separator: ", "))
        if arguments.contains("--text") {
            print("title: " + reading.text.title)
            print("focused: " + reading.text.focused.replacingOccurrences(of: "\n", with: "⏎"))
            for piece in reading.text.visible { print("visible: " + piece.replacingOccurrences(of: "\n", with: "⏎")) }
        }
    }
}
