import Foundation
import Testing
@testable import Common

@Suite("KeyHelp")
struct KeyHelpTests {
    @Test("the keys live in the menu, not behind a key: ⌘/ is nobody's, and no row names it")
    func noHelpKey() {
        #expect(FilterKey(command: "/", shift: false) == nil && !(KeyHelp.map + KeyHelp.strip).contains { $0.keys == "⌘/" })
    }

    @Test("the README's two key tables are the menu's rows, word for word: one source")
    func readmeIsPinned() throws {
        let readme = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("README.md"), encoding: .utf8)
        for row in KeyHelp.map + KeyHelp.strip {
            #expect(readme.contains("| \(row.keys) | \(row.does) |"), "README lacks: \(row.keys)")
        }
        #expect(KeyHelp.map.count >= 8 && KeyHelp.strip.count >= 8 && !readme.contains("⌘/"))
    }
}
