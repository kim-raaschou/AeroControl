import CoreGraphics

/// Adaptive fit-to-screen sizing for the AeroControl strip (Cmd-Tab style).
///
/// The preferred icon size (from the settings menu) is treated as the *preferred /
/// maximum* icon size. When the workspaces' natural main-axis length would exceed the
/// available screen extent, the rendered ("effective") icon size shrinks so everything
/// fits — content is never clipped. When there is room to spare, the preferred size is
/// used.
///
/// Because every metric in `AeroControlMetrics` is proportional to `iconSize` (the
/// single-scale model), the main-axis length is **linear** in the icon size. So one
/// division yields the exact fitting size — no iteration, and the re-layout stays crisp
/// (we change the real size, not a blurry transform). The card's main-axis length uses
/// the same formula in both orientations, so `rowWidth` doubles as the column *height*
/// for a vertical widget.
public enum AeroControlLayout {
    /// Fraction of the screen's available extent the widget may fill before its icons
    /// start shrinking — the remainder is breathing room from the screen edge.
    public static let usableScreenFraction: CGFloat = 0.8

    /// Total main-axis length the workspace row (or column) occupies at a given icon
    /// size — width for a horizontal widget, height for a vertical one (the per-card
    /// formula is identical on both axes). `windowCounts` is one entry per shown
    /// workspace: the number of app icons it holds (0 = an empty workspace, rendered as
    /// a compact pill).
    public static func rowWidth(iconSize: CGFloat, windowCounts: [Int]) -> CGFloat {
        guard !windowCounts.isEmpty else { return 0 }
        let m = AeroControlMetrics(iconSize: iconSize)
        var total: CGFloat = 0
        for count in windowCounts {
            if count <= 0 {
                total += m.emptyCardWidth
            } else {
                let n = CGFloat(count)
                let tileWidth = m.iconSize + 2 * m.tileCellPadding
                total += 2 * m.cardHorizontalPadding
                    + n * tileWidth
                    + (n - 1) * m.appRowSpacing
            }
        }
        total += CGFloat(windowCounts.count - 1) * m.cardSpacing
        return total
    }

    /// The rendered icon size: the preferred size when the row fits, otherwise the
    /// largest size at which the whole row fits `availableWidth`. Never exceeds
    /// `preferred`; keeps shrinking below any comfort target so nothing clips.
    ///
    /// Row width is piecewise-linear in the icon size — linear *through the origin*
    /// above the focus-plate padding floor, and *affine* (a fixed per-card term from the
    /// floored padding) below it. We solve within whichever piece the fitting size lands
    /// in, so the row fills the available width exactly instead of overshooting by the
    /// floor's constant when the icons shrink small.
    public static func effectiveIconSize(
        preferred: CGFloat,
        availableWidth: CGFloat,
        windowCounts: [Int]
    ) -> CGFloat {
        let pref = AeroControlMetrics.sanitizedIconSize(preferred)
        guard availableWidth > 0, !windowCounts.isEmpty else { return pref }
        let floorSize = AeroControlMetrics.focusPlateFloorIconSize
        // Above the floor the width is linear through the origin, so one division gives
        // the exact fit.
        let slopeAbove = rowWidth(iconSize: floorSize, windowCounts: windowCounts) / floorSize
        guard slopeAbove > 0 else { return pref }
        let fitAbove = availableWidth / slopeAbove
        if fitAbove >= floorSize { return min(pref, fitAbove) }
        // Below the floor the width gains a constant per-card term: fit the affine model
        // from two samples in that regime and solve exactly.
        let widthAtHalf = rowWidth(iconSize: floorSize / 2, windowCounts: windowCounts)
        let widthAtFloor = rowWidth(iconSize: floorSize, windowCounts: windowCounts)
        let slopeBelow = (widthAtFloor - widthAtHalf) / (floorSize / 2)
        guard slopeBelow > 0 else { return min(pref, fitAbove) }
        let intercept = widthAtFloor - slopeBelow * floorSize
        let fitBelow = (availableWidth - intercept) / slopeBelow
        return min(pref, max(1, fitBelow))
    }
}
