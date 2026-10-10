import Foundation
import Testing
@testable import Common

@Suite("KeyHelp")
struct KeyHelpTests {
    @Test("⌘/ is the help key")
    func helpKey() {
        #expect(FilterKey(command: "/", shift: false) == .help)
    }

    @Test("the README's two key tables are the help's rows, word for word: one source")
    func readmeIsPinned() throws {
        let readme = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("README.md"), encoding: .utf8)
        for row in KeyHelp.map + KeyHelp.strip {
            #expect(readme.contains("| \(row.keys) | \(row.does) |"), "README lacks: \(row.keys)")
        }
        #expect(KeyHelp.map.count >= 8 && KeyHelp.strip.count >= 8 && KeyHelp.map.last?.keys == "⌘/" && KeyHelp.strip.last?.keys == "⌘/")
    }
}
