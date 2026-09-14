import CoreGraphics

public enum AeroControlLayout {
    public static let usableScreenFraction: CGFloat = 0.8
    /// Preferred icon size in the full-screen presentation; previews are 3:2 of it
    /// (240x160 pt) and the width fit shrinks it when a row would not fit.
    public static let fullscreenIconSize: CGFloat = 80

    public static func rowWidth(iconSize: CGFloat, windowCounts: [Int], previews: Bool = false) -> CGFloat {
        guard !windowCounts.isEmpty else { return 0 }
        let m = AeroControlMetrics(iconSize: iconSize, previews: previews)
        var total: CGFloat = 0
        for count in windowCounts {
            if count <= 0 {
                total += m.emptyCardWidth
            } else {
                let n = CGFloat(count)
                let tileWidth = m.tileWidth
                total += m.cardHorizontalPadding + m.badgeGutter
                    + n * tileWidth
                    + (n - 1) * m.appRowSpacing
            }
        }
        total += CGFloat(windowCounts.count - 1) * m.cardSpacing
        return total
    }

    public static func effectiveIconSize(
        preferred: CGFloat,
        availableWidth: CGFloat,
        windowCounts: [Int],
        previews: Bool = false
    ) -> CGFloat {
        let pref = AeroControlMetrics.sanitizedIconSize(preferred)
        guard availableWidth > 0, !windowCounts.isEmpty else { return pref }
        let floorSize = AeroControlMetrics.focusPlateFloorIconSize
        let slopeAbove = rowWidth(iconSize: floorSize, windowCounts: windowCounts, previews: previews) / floorSize
        guard slopeAbove > 0 else { return pref }
        let fitAbove = availableWidth / slopeAbove
        if fitAbove >= floorSize { return min(pref, fitAbove) }
        let widthAtHalf = rowWidth(iconSize: floorSize / 2, windowCounts: windowCounts, previews: previews)
        let widthAtFloor = rowWidth(iconSize: floorSize, windowCounts: windowCounts, previews: previews)
        let slopeBelow = (widthAtFloor - widthAtHalf) / (floorSize / 2)
        guard slopeBelow > 0 else { return min(pref, fitAbove) }
        let intercept = widthAtFloor - slopeBelow * floorSize
        let fitBelow = (availableWidth - intercept) / slopeBelow
        return min(pref, max(1, fitBelow))
    }
}
