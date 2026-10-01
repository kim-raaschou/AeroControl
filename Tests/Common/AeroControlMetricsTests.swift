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
        let gap = AeroControlMetrics.snapshotRingGap
        #expect(AeroControlMetrics.focusPlateRect(around: CGSize(width: 96, height: 96)) == CGSize(width: 96 + 2 * gap, height: 96 + 2 * gap))
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
