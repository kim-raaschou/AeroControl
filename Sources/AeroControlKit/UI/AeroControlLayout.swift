import CoreGraphics

public enum AeroControlLayout {
    public static let usableScreenFraction: CGFloat = 0.8

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

    public static func effectiveIconSize(
        preferred: CGFloat,
        availableWidth: CGFloat,
        windowCounts: [Int]
    ) -> CGFloat {
        let pref = AeroControlMetrics.sanitizedIconSize(preferred)
        guard availableWidth > 0, !windowCounts.isEmpty else { return pref }
        let floorSize = AeroControlMetrics.focusPlateFloorIconSize
        let slopeAbove = rowWidth(iconSize: floorSize, windowCounts: windowCounts) / floorSize
        guard slopeAbove > 0 else { return pref }
        let fitAbove = availableWidth / slopeAbove
        if fitAbove >= floorSize { return min(pref, fitAbove) }
        let widthAtHalf = rowWidth(iconSize: floorSize / 2, windowCounts: windowCounts)
        let widthAtFloor = rowWidth(iconSize: floorSize, windowCounts: windowCounts)
        let slopeBelow = (widthAtFloor - widthAtHalf) / (floorSize / 2)
        guard slopeBelow > 0 else { return min(pref, fitAbove) }
        let intercept = widthAtFloor - slopeBelow * floorSize
        let fitBelow = (availableWidth - intercept) / slopeBelow
        return min(pref, max(1, fitBelow))
    }
}
