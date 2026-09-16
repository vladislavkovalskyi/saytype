import Carbon.HIToolbox
import Testing
import VMCore
@testable import VMSystem

@Suite struct KeyShortcutTests {
    @Test func globalShortcutsNeedAModifierUnlessFunctionKey() {
        #expect(KeyShortcut.pasteAgain.isAllowed)
        #expect(KeyShortcut(keyCode: kVK_ANSI_M, option: true).isAllowed)
        #expect(KeyShortcut(keyCode: kVK_ANSI_V, command: true, shift: true).isAllowed)
        #expect(KeyShortcut(keyCode: kVK_F5).isAllowed)
        #expect(!KeyShortcut(keyCode: kVK_ANSI_V).isAllowed)
        #expect(!KeyShortcut(keyCode: kVK_ANSI_V, shift: true).isAllowed)
        // ⌘V is the app's own paste: taking it globally would break pasting everywhere.
        #expect(!KeyShortcut(keyCode: kVK_ANSI_V, command: true).isAllowed)
    }

    @MainActor
    @Test func namesUseMacOSModifierOrder() {
        let shortcut = KeyShortcut(keyCode: kVK_F13, control: true, option: true, command: true, shift: true)
        #expect(shortcut.symbols == ["⌃", "⌥", "⇧", "⌘", "F13"])
        #expect(KeyShortcut(keyCode: kVK_Space, option: true).displayName == "⌥Space")
        #expect(KeyShortcut.pasteAgain.displayName == "⌃⌥V")
    }
}
