import CoreGraphics

/// The sizes of one tile: a window snapshot cell, shaped like the screen its window is on.
public struct AeroControlMetrics: Equatable, Sendable {
    /// The drawn tile, before cell padding.
    public let tileSize: CGSize
    /// Room around the tile inside its grid cell, so neighbours never touch.
    public let tileCellPadding: CGFloat

    /// Height/width of a cell when nothing better is known; 2:3 is the neutral default.
    public static let defaultAspect: CGFloat = 2.0 / 3.0
    /// Padding as a share of the tile's width, so it scales with the grid: 2 pt on a 144 pt tile.
    private static let paddingFraction: CGFloat = 2.0 / 144.0

    /// Metrics whose padded tile (`tileWidth`) is exactly `cellWidth`, so a grid of such
    /// cells fills the card's inner width without overflowing it. `aspect` is height/width.
    public static func fitting(cellWidth: CGFloat, aspect: CGFloat = defaultAspect) -> AeroControlMetrics {
        let width = cellWidth / (1 + 2 * paddingFraction)
        return AeroControlMetrics(tileSize: CGSize(width: width, height: width * aspect),
                                  tileCellPadding: width * paddingFraction)
    }

    /// The tile and its padding: what one grid cell takes.
    public var tileWidth: CGFloat { tileSize.width + 2 * tileCellPadding }

    /// `imageSize` scaled to sit inside `box` with its own aspect ratio; the box itself when
    /// the image has no size to speak of.
    public static func fit(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Gap between a snapshot and its focus ring: a few points, whatever the tile size.
    public static let snapshotRingGap: CGFloat = 4
    /// Stroke of the focus ring: a hairline that does not scale with the tile.
    public static let focusRingWidth: CGFloat = 2
    /// Corner radius of a snapshot; small, like a real window's corners.
    public static let snapshotRadius: CGFloat = 6

    /// The focus ring's frame around a snapshot of the given drawn size.
    public static func focusPlateRect(around content: CGSize) -> CGSize {
        CGSize(width: content.width + 2 * snapshotRingGap, height: content.height + 2 * snapshotRingGap)
    }
}
