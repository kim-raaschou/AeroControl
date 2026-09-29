import CoreGraphics

/// The sizes of one tile, as `TilePacker` placed it.
public struct AeroControlMetrics: Equatable, Sendable {
    /// The drawn tile: picture plus caption lane, when there is one.
    public let tileSize: CGSize

    public init(tileSize: CGSize) { self.tileSize = tileSize }

    /// The app icon in a picture's corner: small enough never to compete with the picture.
    public var badgeSize: CGFloat { min(28, max(16, tileSize.width * 0.06)) }

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
