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
