import AppKit
import Testing
@testable import VMSystem

@Suite @MainActor struct PasteboardTests {
    @Test func snapshotRestoresEveryItemAndType() {
        let board = NSPasteboard(name: .init("saytype.tests.\(UUID().uuidString)"))
        board.clearContents()
        let first = NSPasteboardItem()
        first.setString("первый", forType: .string)
        first.setData(Data([1, 2, 3]), forType: .init("com.example.binary"))
        let second = NSPasteboardItem()
        second.setString("https://example.com", forType: .URL)
        board.writeObjects([first, second])

        let snapshot = PasteboardSnapshot(board)
        board.clearContents()
        board.setString("временный", forType: .string)
        snapshot.restore(to: board)

        let items = board.pasteboardItems ?? []
        #expect(items.count == 2)
        #expect(items.first?.string(forType: .string) == "первый")
        #expect(items.first?.data(forType: .init("com.example.binary")) == Data([1, 2, 3]))
        #expect(items.last?.string(forType: .URL) == "https://example.com")
        board.releaseGlobally()
    }

    @Test func findsTheVKeyInTheCurrentLayout() {
        // On QWERTY-based layouts V is ANSI keycode 9.
        #expect(KeyPoster.keycode(for: "v") == 9)
    }
}
