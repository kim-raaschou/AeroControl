import AppKit
import Testing
@testable import AeroControl

struct BordersTests {
    @Test("a colour is written for borders as six hex digits, rrggbb, in sRGB")
    func hex() {
        #expect(Borders.hex(NSColor(srgbRed: 1, green: 0.5, blue: 0, alpha: 1)) == "ff8000" && Borders.hex(.black) == "000000")
    }
}
