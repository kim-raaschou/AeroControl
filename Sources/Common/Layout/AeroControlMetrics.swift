import CoreGraphics

public enum AeroControlMetrics {
    public static func badgeSize(width: CGFloat) -> CGFloat { min(36, max(22, width * 0.11)) }

    public static func fit(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    public static func cover(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = max(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    public static func pixelSnapped(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(1, (size.width * scale).rounded()) / scale, height: max(1, (size.height * scale).rounded()) / scale)
    }

    public static func focusRingWidth(scale: CGFloat) -> CGFloat { 1 + scale }
    public static let snapshotRadius: CGFloat = 6
}
