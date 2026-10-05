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
    @Test("tiles are a row or a column, an accordion one window in front of another; one window says how the next will go; none, or no known layout, no symbol", arguments: [
        ("h_tiles", 2, "rectangle.split.2x1"), ("v_tiles", 3, "rectangle.split.1x2"), ("h_accordion", 2, "rectangle.on.rectangle"),
        ("v_accordion", 2, "rectangle.on.rectangle"), ("h_tiles", 1, "rectangle.split.2x1"), ("h_accordion", 1, "rectangle.on.rectangle"),
        ("h_tiles", 0, nil), ("", 3, nil), ("floating", 3, nil),
    ] as [(String, Int, String?)])
    func symbols(layout: String, windows: Int, symbol: String?) {
        #expect(AeroControlLayout.layoutSymbol(rootLayout: layout, windowCount: windows)?.name == symbol)
    }

    @Test("each says in words what AeroSpace does with the windows")
    func words() {
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_tiles", windowCount: 2)?.help == "Tiles: windows side by side")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "v_tiles", windowCount: 2)?.help == "Tiles: windows one above another")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_accordion", windowCount: 2)?.help == "Accordion: windows stacked, one in front")
    }
}

@Suite("the app icon on a picture")
struct BadgeSizeTests {
    @Test("about a ninth of the picture's width, kept between 22 and 36 points so it can be read")
    func badgeSize() {
        func size(_ w: CGFloat) -> CGFloat { AeroControlMetrics.badgeSize(width: w) }
        #expect(size(100) == 22 && size(200) == 22)
        #expect(abs(size(300) - 33) < 0.001)
        #expect(size(400) == 36 && size(900) == 36)
    }
}
