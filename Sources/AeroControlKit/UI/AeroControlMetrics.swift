import CoreGraphics

/// The sizes of one tile, as `TilePacker` placed it.
public struct AeroControlMetrics: Equatable, Sendable {
    /// The drawn tile: picture plus caption lane, when there is one.
    public let tileSize: CGSize

    public init(tileSize: CGSize) { self.tileSize = tileSize }

    /// The app icon in a picture's corner: about a ninth of the picture's width, between 22 and 36 points —
    /// small enough not to compete with the picture, large enough to tell a terminal from an editor at a glance.
    public var badgeSize: CGFloat { min(36, max(22, tileSize.width * 0.11)) }

    /// `imageSize` scaled to sit inside `box` with its own aspect ratio; the box itself when
    /// the image has no size to speak of.
    public static func fit(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// `size` rounded to the screen's pixels, at least one each way: drawn at that size a
    /// picture of exactly that many pixels maps one to one onto the screen.
    public static func pixelSnapped(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(1, (size.width * scale).rounded()) / scale, height: max(1, (size.height * scale).rounded()) / scale)
    }

    /// Stroke of the focus ring, laid on the picture's edge: thin, and the same at every size.
    public static let focusRingWidth: CGFloat = 2.5
    /// Corner radius of a snapshot; small, like a real window's corners.
    public static let snapshotRadius: CGFloat = 6

    /// The focus ring's frame for a snapshot of the given drawn size: the picture's own. The ring
    /// lies on the picture's edge with the picture's corners, so it can never run into a
    /// neighbour drawn at AeroSpace's few points of gap, nor be cut off by the card's edge.
    public static func focusPlateRect(around content: CGSize) -> CGSize { content }
}
