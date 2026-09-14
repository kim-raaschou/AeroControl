import Testing
import CoreGraphics
@testable import AeroControlKit

@Suite("AeroControlMetrics")
struct AeroControlMetricsTests {
    @Test func acceptsSmallSize() {
        #expect(AeroControlMetrics(iconSize: 10).iconSize == 10)
    }

    @Test func acceptsLargeSize() {
        #expect(AeroControlMetrics(iconSize: 200).iconSize == 200)
    }

    @Test func nonPositiveFallsBackToDefault() {
        #expect(AeroControlMetrics(iconSize: 0).iconSize == 48)
        #expect(AeroControlMetrics(iconSize: -5).iconSize == 48)
    }

    @Test func keepsInRange() {
        #expect(AeroControlMetrics(iconSize: 48).iconSize == 48)
    }

    @Test func detailMetricsScaleAndFloor() {
        let tiny = AeroControlMetrics(iconSize: 16)
        let big = AeroControlMetrics(iconSize: 96)
        // Corner radius scales with the icon and stays concentric with the focus plate
        // (card nests *outside* the plate: cardRadius = plateRadius + plate→card gap).
        #expect(tiny.cornerRadius < big.cornerRadius)
        #expect(big.cornerRadius > big.focusPlateRadius)
        #expect(tiny.cornerRadius > tiny.focusPlateRadius)
        // Badge text is a fixed fraction (0.58) of the badge diameter, floored at
        // 8pt for legibility when workspaces are numerous and icons auto-shrink.
        #expect(tiny.badgeFontSize == tiny.badgeDiameter * 0.58)
        #expect(big.badgeFontSize > tiny.badgeFontSize)
        #expect(big.appRowSpacing > tiny.appRowSpacing)
    }

    @Test func referenceSizeYieldsDesignValues() {
        // At the reference icon size, the plain design literals apply directly.
        // cornerRadius and cardHorizontalPadding are intentionally omitted: both are
        // derived from the focus-plate geometry (concentric corners), not plain
        // design values (see AeroControlMetrics).
        let m = AeroControlMetrics(iconSize: AeroControlMetrics.defaultIconSize)
        #expect(m.badgeFontSize == m.badgeDiameter * 0.58)
        #expect(m.appRowSpacing == 8)
        #expect(m.tileCellPadding == 2)
    }

    @Test func cardHeightGrowsWithIcon() {
        let small = AeroControlMetrics(iconSize: 32).cardHeight
        let normal = AeroControlMetrics(iconSize: 48).cardHeight
        let large = AeroControlMetrics(iconSize: 64).cardHeight
        #expect(small < normal)
        #expect(normal < large)
        #expect(large > 0)
    }
}

@Suite("Widget layout")
struct WidgetLayoutTests {
    @Test func orientationIsVertical() {
        #expect(Orientation.horizontal.isVertical == false)
        #expect(Orientation.vertical.isVertical == true)
    }

    @Test func dockEdgeDerivesOrientation() {
        #expect(DockEdge.top.orientation == .horizontal)
        #expect(DockEdge.bottom.orientation == .horizontal)
        #expect(DockEdge.left.orientation == .vertical)
        #expect(DockEdge.right.orientation == .vertical)
    }
}
