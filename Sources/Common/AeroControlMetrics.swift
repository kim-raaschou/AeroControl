import CoreGraphics

/// The sizes of a tile's parts.
public enum AeroControlMetrics {
    /// The app icon in a picture's corner, for a tile `width` wide: about a ninth of it, between 22
    /// and 36 points — small enough not to compete with the picture, large enough to tell a
    /// terminal from an editor at a glance.
    public static func badgeSize(width: CGFloat) -> CGFloat { min(36, max(22, width * 0.11)) }

    /// `imageSize` scaled to sit inside `box` with its own aspect ratio; the box itself when the
    /// image has no size to speak of.
    public static func fit(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// `imageSize` scaled to cover `box` with its own aspect ratio, the overhang to be cut; the box
    /// itself when the image has no size to speak of.
    public static func cover(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = max(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// `size` rounded to the screen's pixels, at least one each way: drawn at that size a picture
    /// of exactly that many pixels maps one to one onto the screen.
    public static func pixelSnapped(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(1, (size.width * scale).rounded()) / scale, height: max(1, (size.height * scale).rounded()) / scale)
    }

    /// Stroke of the focus ring, laid on the picture's edge: about 0.6 mm on any screen, in whole
    /// pixels — one point and one more per pixel the point holds, so 2 px at 1x (~100 ppi) and 6 px
    /// on Retina (~250 ppi).
    public static func focusRingWidth(scale: CGFloat) -> CGFloat { 1 + scale }
    /// Corner radius of a snapshot; small, like a real window's corners.
    public static let snapshotRadius: CGFloat = 6
}
