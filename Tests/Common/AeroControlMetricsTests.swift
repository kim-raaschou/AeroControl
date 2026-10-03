import Testing
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

    @Test("the focus ring is 2.5 pt in whole pixels: five on a Retina screen, three at 1x, where two and a half blurred")
    func focusRingWholePixels() {
        #expect(AeroControlMetrics.focusRingWidth(scale: 2) == 2.5)
        #expect(AeroControlMetrics.focusRingWidth(scale: 1) == 3)
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
    @Test("tiles are a row or a column, an accordion one window in front of another")
    func symbols() {
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_tiles", windowCount: 2)?.name == "rectangle.split.2x1")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "v_tiles", windowCount: 3)?.name == "rectangle.split.1x2")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_accordion", windowCount: 2)?.name == "rectangle.on.rectangle")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "v_accordion", windowCount: 2)?.name == "rectangle.on.rectangle")
    }

    @Test("each says in words what AeroSpace does with the windows")
    func words() {
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_tiles", windowCount: 2)?.help == "Tiles: windows side by side")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "v_tiles", windowCount: 2)?.help == "Tiles: windows one above another")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_accordion", windowCount: 2)?.help == "Accordion: windows stacked, one in front")
    }

    @Test("one window still says how the next one will be arranged; an empty workspace and an unknown layout have no symbol")
    func none() {
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_tiles", windowCount: 1)?.name == "rectangle.split.2x1")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_accordion", windowCount: 1)?.name == "rectangle.on.rectangle")
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "h_tiles", windowCount: 0) == nil)
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "", windowCount: 3) == nil)
        #expect(AeroControlLayout.layoutSymbol(rootLayout: "floating", windowCount: 3) == nil)
    }
}

@Suite("the app icon on a picture")
struct BadgeSizeTests {
    @Test("about a ninth of the picture's width, kept between 22 and 36 points so it can be read")
    func badgeSize() {
        func size(_ w: CGFloat) -> CGFloat { AeroControlMetrics(tileSize: CGSize(width: w, height: 100)).badgeSize }
        #expect(size(100) == 22 && size(200) == 22)
        #expect(abs(size(300) - 33) < 0.001)
        #expect(size(400) == 36 && size(900) == 36)
    }
}
