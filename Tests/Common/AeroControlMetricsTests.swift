import Testing
import CoreGraphics
@testable import AeroControlKit

@Suite("AeroControlMetrics")
struct AeroControlMetricsTests {
    @Test("fitting makes the padded tile exactly the cell width, shaped by the aspect")
    func fitting() {
        let m = AeroControlMetrics.fitting(cellWidth: 300, aspect: 2.0 / 3.0)
        #expect(abs(m.tileWidth - 300) < 0.001)
        #expect(abs(m.tileSize.height - m.tileSize.width * 2 / 3) < 0.001)
        #expect(m.tileCellPadding > 0 && m.tileCellPadding < 10)
        #expect(AeroControlMetrics.fitting(cellWidth: 600).tileCellPadding == 2 * m.tileCellPadding)   // scales with the grid
    }

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
