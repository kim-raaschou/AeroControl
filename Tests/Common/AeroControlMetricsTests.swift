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
        // Text stays legible at tiny sizes (floored at 9pt), yet grows with the icon.
        #expect(tiny.badgeFontSize == 9)
        #expect(big.badgeFontSize > tiny.badgeFontSize)
        #expect(big.appRowSpacing > tiny.appRowSpacing)
    }

    @Test func referenceSizeYieldsDesignValues() {
        // At the reference icon size, the plain design literals apply directly.
        // cornerRadius and cardHorizontalPadding are intentionally omitted: both are
        // derived from the focus-plate geometry (concentric corners), not plain
        // design values (see AeroControlMetrics).
        let m = AeroControlMetrics(iconSize: AeroControlMetrics.defaultIconSize)
        #expect(m.badgeFontSize == AeroControlMetrics.defaultIconSize * 0.20)
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

@Suite("AeroControlLayout fit-to-screen")
struct AeroControlLayoutTests {
    @Test func fewAppsUsePreferredSize() {
        // A couple of small workspaces on a wide screen: nothing to shrink.
        let size = AeroControlLayout.effectiveIconSize(
            preferred: 48, availableWidth: 3000, windowCounts: [3, 1, 0])
        #expect(size == 48)
    }

    @Test func manyAppsShrinkToFit() {
        // A crowded row on a narrow screen must shrink below the preferred size.
        let size = AeroControlLayout.effectiveIconSize(
            preferred: 96, availableWidth: 800, windowCounts: [30])
        #expect(size < 96)
        #expect(size > 0)
    }

    @Test func neverExceedsPreferred() {
        let size = AeroControlLayout.effectiveIconSize(
            preferred: 48, availableWidth: 100_000, windowCounts: [5, 5, 5])
        #expect(size == 48)
    }

    @Test func shrinkSizeExactlyFillsWidth() {
        // At the fitting size, the row width equals the available width.
        let counts = [7, 3, 0, 2]
        let avail: CGFloat = 900
        let size = AeroControlLayout.effectiveIconSize(
            preferred: 200, availableWidth: avail, windowCounts: counts)
        let width = AeroControlLayout.rowWidth(iconSize: size, windowCounts: counts)
        #expect(abs(width - avail) < 0.5)
    }

    @Test func emptyWorkspacesAreCounted() {
        // Empty pills still consume width, so more of them means a smaller fit.
        let base = AeroControlLayout.effectiveIconSize(
            preferred: 96, availableWidth: 600, windowCounts: [5])
        let withEmpties = AeroControlLayout.effectiveIconSize(
            preferred: 96, availableWidth: 600, windowCounts: [5, 0, 0, 0])
        #expect(withEmpties < base)
    }

    @Test func widerScreenAllowsBiggerIcons() {
        let counts = [10, 4]
        let narrow = AeroControlLayout.effectiveIconSize(
            preferred: 96, availableWidth: 600, windowCounts: counts)
        let wide = AeroControlLayout.effectiveIconSize(
            preferred: 96, availableWidth: 1200, windowCounts: counts)
        #expect(wide > narrow)
    }

    @Test func emptyInputUsesPreferred() {
        #expect(AeroControlLayout.effectiveIconSize(
            preferred: 48, availableWidth: 1000, windowCounts: []) == 48)
    }
}
