import Common
import CoreGraphics

/// The overview's layout constants, and the two pure engines wired to them: `CardGrid`
/// places the workspace cards (widths by weight, rows broken where the windows come out
/// largest, row heights that follow the content), `TilePacker` places the windows inside
/// a card (each at its own shape, one shared picture height). All unit-tested.
public enum AeroControlLayout {
    public static let usableScreenFraction: CGFloat = 0.94
    public static let cardGap: CGFloat = 24
    public static let tileSpacing: CGFloat = 14
    public static let cardPadding: CGFloat = 18
    /// Vertical room reserved at the top of a card for the workspace badge.
    public static let badgeLane: CGFloat = 44
    /// Diameter of the workspace badge in the card header.
    public static let badgeSize: CGFloat = 24
    /// An empty card is exactly the badge plus the card padding on both sides, so the badge
    /// sits in the same corner as on full cards and is centered in the narrow card as well.
    public static let emptyCardWidth: CGFloat = badgeSize + 2 * cardPadding
    /// Wider empty card: room for the badge AND the display name beside it, used when the
    /// workspaces span more than one display.
    public static let namedEmptyCardWidth: CGFloat = emptyCardWidth + 82
    /// While a filter is up each tile carries a caption above its picture: a title line and
    /// the gap to the picture. Both the tile and `usedHeight` budget for it from here.
    public static let captionTitleHeight: CGFloat = 32
    public static let captionGap: CGFloat = 6
    public static let captionLane: CGFloat = captionTitleHeight + captionGap

    /// Width / height of a window nothing is known about yet: the screen's own shape.
    public static func screenRatio(for available: CGSize) -> CGFloat {
        available.height > 0 ? available.width / available.height : 1.5
    }

    /// Width / height of each window, from its measured size, the screen's when unmeasured.
    public static func ratios(of windows: [WindowInfo], sizes: [Int: CGSize], fallback: CGFloat) -> [CGFloat] {
        windows.map { window in
            guard let size = sizes[window.windowId], size.width > 0, size.height > 0 else { return fallback }
            return size.width / size.height
        }
    }

    /// A card's height that is not pictures: the padding, the badge lane, and the gap
    /// between the badge and the first row of tiles.
    public static let cardChrome: CGFloat = cardPadding + badgeLane + tileSpacing

    /// The room inside a card for its tiles: below the badge lane and its gap, inside the padding.
    public static func innerSize(of card: CGSize) -> CGSize {
        CGSize(width: card.width - 2 * cardPadding, height: card.height - cardChrome)
    }

    /// A card's tiles as drawn: `TilePacker` at the largest picture height that fits `inner`,
    /// with `caption` under each tile (the caption lane while filtering, nothing on the map).
    public static func packTiles(ratios: [CGFloat], inner: CGSize, caption: CGFloat) -> TilePacker.Packed {
        let height = TilePacker.packHeight(ratios: ratios, width: inner.width, height: inner.height,
                                           gap: tileSpacing, caption: caption, scales: nil)
        return TilePacker.packRows(ratios: ratios, tileHeight: max(1, height), width: inner.width,
                                   gap: tileSpacing, caption: caption, scales: nil)
    }

    /// A card's weight in the grid: an empty workspace is a strip, one to three windows an
    /// ordinary card, four or more a double share. Three steps, not a slope, so cards hold
    /// still through ordinary window churn.
    public static func weight(forCount count: Int) -> CGFloat {
        count == 0 ? 0 : (count >= 4 ? 2 : 1)
    }

    /// `CardGrid`'s options for this overview: its gaps and paddings, the screen's shape as
    /// the proxy tile, the caption lane while filtering.
    public static func cardGridOptions(for available: CGSize, emptyWidth: CGFloat, caption: CGFloat) -> CardGrid.Options {
        var options = CardGrid.Options(gap: cardGap, tileRatio: screenRatio(for: available), cardPadding: cardPadding,
                                       chrome: cardChrome, narrow: emptyWidth, tileGap: tileSpacing, caption: caption)
        options.cardShape = screenRatio(for: available)
        return options
    }
}
