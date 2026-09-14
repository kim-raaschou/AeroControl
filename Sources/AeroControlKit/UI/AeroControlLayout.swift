import CoreGraphics

/// Pure layout math for the full-screen overview: workspaces in a near-square grid of
/// equal cards (5 → 3 + 2), and each card's windows in a near-square grid of 3:2 tiles
/// sized to fill the card. Everything here is unit-tested; the views only draw.
public enum AeroControlLayout {
    public static let usableScreenFraction: CGFloat = 0.86
    public static let cardGap: CGFloat = 28
    /// Card height as a fraction of its width (a 16:10-ish "desktop").
    public static let cardAspect: CGFloat = 0.62
    /// Tile height as a fraction of its width.
    public static let tileAspect: CGFloat = 2.0 / 3.0
    public static let tileSpacing: CGFloat = 14
    public static let cardPadding: CGFloat = 18
    /// Vertical room reserved at the top of a card for the workspace badge.
    public static let badgeLane: CGFloat = 44
    public static let minTileWidth: CGFloat = 36

    public static func columns(forCount count: Int) -> Int {
        count <= 0 ? 0 : Int(Double(count).squareRoot().rounded(.up))
    }

    public static func rows(forCount count: Int) -> Int {
        let columns = columns(forCount: count)
        return columns == 0 ? 0 : Int((Double(count) / Double(columns)).rounded(.up))
    }

    /// Equal card size so `count` cards fit `available` in the near-square grid.
    public static func cardSize(count: Int, available: CGSize) -> CGSize {
        let columns = columns(forCount: count), rows = rows(forCount: count)
        guard columns > 0, available.width > 0, available.height > 0 else { return .zero }
        let width = (available.width - CGFloat(columns - 1) * cardGap) / CGFloat(columns)
        let heightByRows = (available.height - CGFloat(rows - 1) * cardGap) / CGFloat(rows)
        let height = min(heightByRows, width * cardAspect)
        return CGSize(width: (height / cardAspect).rounded(.down), height: height.rounded(.down))
    }

    /// Width of one window tile so `windowCount` tiles fill the card's inner area.
    public static func tileWidth(windowCount: Int, card: CGSize) -> CGFloat {
        guard windowCount > 0 else { return 0 }
        let columns = columns(forCount: windowCount), rows = rows(forCount: windowCount)
        let innerWidth = card.width - 2 * cardPadding
        let innerHeight = card.height - cardPadding - badgeLane
        let byWidth = (innerWidth - CGFloat(columns - 1) * tileSpacing) / CGFloat(columns)
        let byHeight = ((innerHeight - CGFloat(rows - 1) * tileSpacing) / CGFloat(rows)) / tileAspect
        return max(minTileWidth, min(byWidth, byHeight).rounded(.down))
    }
}
