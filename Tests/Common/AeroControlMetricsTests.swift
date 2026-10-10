import Testing
import Common
import CoreGraphics
@testable import AeroControlKit

@Suite("AeroControlMetrics")
struct AeroControlMetricsTests {
    @Test("a snapshot is fitted into the cell with its own aspect ratio, and the focus frame hugs it")
    func fittedPreview() {
        let box = CGSize(width: 144, height: 96)
        #expect(AeroControlMetrics.fit(CGSize(width: 1000, height: 1000), into: box) == CGSize(width: 96, height: 96))
        #expect(AeroControlMetrics.fit(CGSize(width: 600, height: 200), into: box) == CGSize(width: 144, height: 48))
        #expect(AeroControlMetrics.fit(.zero, into: box) == box)
    }

    @Test("a picture covers its box with its own shape, the rest to be cut: the window's slot is the frame, whatever the app made of it")
    func coveringPreview() {
        let box = CGSize(width: 144, height: 96)
        #expect(AeroControlMetrics.cover(CGSize(width: 1000, height: 1000), into: box) == CGSize(width: 144, height: 144))
        #expect(AeroControlMetrics.cover(CGSize(width: 600, height: 200), into: box) == CGSize(width: 288, height: 96))
        #expect(AeroControlMetrics.cover(.zero, into: box) == box)
    }

    @Test("a picture is drawn a whole number of the screen's pixels wide and high, so one of its pixels is one of the screen's")
    func pixelSnapped() {
        #expect(AeroControlMetrics.pixelSnapped(CGSize(width: 100.3, height: 50.7), scale: 1) == CGSize(width: 100, height: 51))
        #expect(AeroControlMetrics.pixelSnapped(CGSize(width: 100.3, height: 50.7), scale: 2) == CGSize(width: 100.5, height: 50.5))
        #expect(AeroControlMetrics.pixelSnapped(CGSize(width: 0.2, height: 0.2), scale: 1) == CGSize(width: 1, height: 1))   // never nothing
    }

    @Test("the focus ring is about 0.6 mm on any screen, in whole pixels: two at 1x (~100 ppi), six on Retina (~250 ppi)")
    func focusRingWholePixels() {
        #expect(AeroControlMetrics.focusRingWidth(scale: 1) * 1 == 2)
        #expect(AeroControlMetrics.focusRingWidth(scale: 2) * 2 == 6)
    }
}

@Suite("where the tiles sit in a card")
struct TileOriginTests {
    @Test("the packed block is centred in the inner box both ways, never placed off it")
    func centred() {
        let inner = CGSize(width: 500, height: 300)
        #expect(AeroControlLayout.tileOrigin(packed: CGSize(width: 300, height: 100), inner: inner) == CGPoint(x: 100, y: 100))
        #expect(AeroControlLayout.tileOrigin(packed: CGSize(width: 301, height: 101), inner: inner) == CGPoint(x: 99, y: 99))   // rounded down
        #expect(AeroControlLayout.tileOrigin(packed: CGSize(width: 600, height: 400), inner: inner) == .zero)                  // too big: pinned
    }
}

@Suite("the layout symbol on a card")
struct LayoutSymbolTests {
    @Test("tiles are a row or a column, an accordion one window in front of another, on an empty workspace too: it says how the next window will go; no known layout, no symbol", arguments: [
        ("h_tiles", "rectangle.split.2x1"), ("v_tiles", "rectangle.split.1x2"), ("h_accordion", "rectangle.on.rectangle"),
        ("v_accordion", "rectangle.on.rectangle"), ("", nil), ("floating", nil),
    ] as [(String, String?)])
    func symbols(layout: String, symbol: String?) {
        #expect(AeroControlLayout.layoutSymbol(rootLayout: layout)?.name == symbol)
    }

    @Test("each says in words what AeroSpace does with the windows")
    func words() {
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_tiles")?.help == "Tiles: windows side by side")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "v_tiles")?.help == "Tiles: windows one above another")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_accordion")?.help == "Accordion: windows stacked, one in front")
    }
}
