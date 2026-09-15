import Testing
import CoreGraphics
@testable import AeroControlKit

@Suite("AeroControlMetrics")
struct AeroControlMetricsTests {
    @Test func acceptsAnySaneSizeAndFallsBackOtherwise() {
        #expect(AeroControlMetrics(iconSize: 10).iconSize == 10)
        #expect(AeroControlMetrics(iconSize: 200).iconSize == 200)
        #expect(AeroControlMetrics(iconSize: 0).iconSize == 48)
        #expect(AeroControlMetrics(iconSize: -5).iconSize == 48)
        #expect(AeroControlMetrics(iconSize: .nan).iconSize == 48)
    }

    @Test func tileGeometryScalesWithTheIcon() {
        let m = AeroControlMetrics(iconSize: 48)
        #expect(m.tileSize == CGSize(width: 48, height: 48))
        #expect(m.tileCellPadding == 2)
        #expect(m.tileWidth == 52 && m.tileHeight == 52)
        #expect(AeroControlMetrics(iconSize: 96).tileWidth == 2 * m.tileWidth)
    }

    @Test func theFocusPlateHugsTheArtworkWithAFloorAtSmallSizes() {
        let tiny = AeroControlMetrics(iconSize: 16)
        #expect(tiny.focusPlatePadding == 3)                       // the floor, not 16 * 0.05
        #expect(abs(AeroControlMetrics(iconSize: 96).focusPlatePadding - 4.8) < 0.001)
        let m = AeroControlMetrics(iconSize: 48)
        #expect(m.focusPlateRect.width < m.tileWidth)              // tighter than the padded cell
        #expect(m.focusPlateRadius > m.iconArtworkRadius)
    }
}
