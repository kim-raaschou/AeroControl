import CoreGraphics

/// The sizes of a tile's parts.
public enum AeroControlMetrics {
    /// The app icon in a picture's corner, for a tile `width` wide: about a ninth of it, between 22 and 36
    /// points — small enough not to compete with the picture, large enough to tell a terminal from an editor at a glance.
    public static func badgeSize(width: CGFloat) -> CGFloat { min(36, max(22, width * 0.11)) }

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

    /// Stroke of the focus ring, laid on the picture's edge: the same at every size, and 2.5 pt
    /// in whole pixels — five on a Retina screen, three at 1x, where two and a half blurred. At
    /// 1.5 pt it went unseen on a card of five windows.
    public static func focusRingWidth(scale: CGFloat) -> CGFloat { (2.5 * scale).rounded() / scale }
    /// Corner radius of a snapshot; small, like a real window's corners.
    public static let snapshotRadius: CGFloat = 6
}
