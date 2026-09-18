import CoreGraphics

public struct AeroControlMetrics: Equatable, Sendable {
    public static let defaultIconSize: CGFloat = 48

    public let iconSize: CGFloat
    /// With previews on, a tile is a window snapshot cell instead of a square app icon.
    public let previews: Bool
    /// Height/width of a snapshot cell. Windows are shaped like the screen they live on,
    /// so the cell follows the screen's aspect; 2:3 is the neutral default.
    public let previewAspect: CGFloat

    public static let defaultPreviewAspect: CGFloat = 2.0 / 3.0

    public init(iconSize: CGFloat, previews: Bool = false, previewAspect: CGFloat = defaultPreviewAspect) {
        self.iconSize = Self.sanitizedIconSize(iconSize)
        self.previews = previews
        self.previewAspect = previewAspect
    }

    public var previewSize: CGSize { CGSize(width: iconSize * 3, height: iconSize * 3 * previewAspect) }

    /// Metrics whose padded tile (`tileWidth`) is exactly `cellWidth`, so a grid of such
    /// cells fills the card's inner width without overflowing it. Both the tile and its
    /// cell padding are linear in the icon size: 3s + 4s/48 for previews, s + 4s/48 for icons.
    public static func fitting(cellWidth: CGFloat, previews: Bool, previewAspect: CGFloat = defaultPreviewAspect) -> AeroControlMetrics {
        let perIcon = (previews ? 3 : 1) + 4 / defaultIconSize
        return AeroControlMetrics(iconSize: cellWidth / perIcon, previews: previews, previewAspect: previewAspect)
    }

    /// The drawn tile, before cell padding: the preview box or the square icon.
    public var tileSize: CGSize { previews ? previewSize : CGSize(width: iconSize, height: iconSize) }

    /// A window snapshot scaled to fit inside `previewSize`, keeping its own aspect ratio.
    /// The snapshot is drawn bare, so this is what the focus frame hugs.
    public func fittedPreviewSize(_ imageSize: CGSize) -> CGSize {
        Self.fit(imageSize, into: previewSize)
    }

    /// `imageSize` scaled to sit inside `box` with its own aspect ratio; the box itself when
    /// the image has no size to speak of.
    public static func fit(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Gap between a bare snapshot and its focus ring: a few points, whatever the tile size.
    public static let snapshotRingGap: CGFloat = 4

    /// Focus frame around a bare snapshot of the given drawn size.
    public func focusPlateRect(around content: CGSize) -> CGSize {
        CGSize(width: content.width + 2 * Self.snapshotRingGap, height: content.height + 2 * Self.snapshotRingGap)
    }

    public static func sanitizedIconSize(_ value: CGFloat) -> CGFloat {
        (value.isFinite && value > 0) ? value : defaultIconSize
    }

    private var scale: CGFloat { iconSize / Self.defaultIconSize }

    public var tileCellPadding: CGFloat { 2 * scale }

    public var tileHeight: CGFloat {
        tileSize.height + 2 * tileCellPadding
    }

    public var tileWidth: CGFloat {
        tileSize.width + 2 * tileCellPadding
    }

    public var focusPlatePadding: CGFloat { max(Self.minPlatePadding, iconSize * Self.platePaddingFraction) }

    private static let minPlatePadding: CGFloat = 3

    private static let platePaddingFraction: CGFloat = 0.05

    private var iconArtworkInset: CGFloat { iconSize * 0.083 }

    public var iconArtworkRadius: CGFloat { (iconSize - 2 * iconArtworkInset) * 0.22 }

    public var focusPlateRadius: CGFloat { iconArtworkRadius + focusPlatePadding }

    /// App icon badged on a snapshot: small enough never to compete with the image.
    public var previewBadgeSize: CGFloat { min(28, max(16, iconSize * 0.18)) }

    /// Stroke of the focus ring around a tile: a hairline that does not scale with the tile.
    public static let focusRingWidth: CGFloat = 2

    /// Corner radius of a bare window snapshot; small, like a real window's corners.
    public static let snapshotRadius: CGFloat = 6

    /// Selection plate around an icon tile.
    public var focusPlateRect: CGSize {
        CGSize(width: tileSize.width - 2 * iconArtworkInset + 2 * focusPlatePadding,
               height: tileSize.height - 2 * iconArtworkInset + 2 * focusPlatePadding)
    }

}
