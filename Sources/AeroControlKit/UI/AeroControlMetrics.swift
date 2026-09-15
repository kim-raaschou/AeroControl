import CoreGraphics

public struct AeroControlMetrics: Equatable, Sendable {
    public static let defaultIconSize: CGFloat = 48

    public let iconSize: CGFloat
    /// With previews on, a tile is a 3:2 window snapshot instead of a square app icon.
    public let previews: Bool

    public init(iconSize: CGFloat, previews: Bool = false) {
        self.iconSize = Self.sanitizedIconSize(iconSize)
        self.previews = previews
    }

    public var previewSize: CGSize { CGSize(width: iconSize * 3, height: iconSize * 2) }

    /// The drawn tile, before cell padding: the preview box or the square icon.
    public var tileSize: CGSize { previews ? previewSize : CGSize(width: iconSize, height: iconSize) }

    /// A window snapshot scaled to fit inside `previewSize`, keeping its own aspect ratio.
    /// The snapshot is drawn bare, so this is what the focus frame hugs.
    public func fittedPreviewSize(_ imageSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return previewSize }
        let scale = min(previewSize.width / imageSize.width, previewSize.height / imageSize.height)
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

    private static let minTextSize: CGFloat = 7

    private var scale: CGFloat { iconSize / Self.defaultIconSize }

    public var tileCellPadding: CGFloat { 2 * scale }

    public var tileHeight: CGFloat {
        tileSize.height + 2 * tileCellPadding
    }

    public var tileWidth: CGFloat {
        tileSize.width + 2 * tileCellPadding
    }

    public var appRowSpacing: CGFloat { 8 * scale }

    public var focusPlatePadding: CGFloat { max(Self.minPlatePadding, iconSize * Self.platePaddingFraction) }

    private static let minPlatePadding: CGFloat = 3

    private static let platePaddingFraction: CGFloat = 0.05

    public static var focusPlateFloorIconSize: CGFloat { minPlatePadding / platePaddingFraction }

    private var iconArtworkInset: CGFloat { iconSize * 0.083 }

    public var iconArtworkRadius: CGFloat { (iconSize - 2 * iconArtworkInset) * 0.22 }

    public var focusPlateRadius: CGFloat { iconArtworkRadius + focusPlatePadding }

    /// Stroke of the focus ring around a tile: a hairline that does not scale with the tile.
    public static let focusRingWidth: CGFloat = 2

    /// Corner radius of a bare window snapshot; small, like a real window's corners.
    public static let snapshotRadius: CGFloat = 6

    public var focusPlateSize: CGFloat { iconSize - 2 * iconArtworkInset + 2 * focusPlatePadding }

    /// Selection plate around a tile; equals a `focusPlateSize` square for icon tiles.
    public var focusPlateRect: CGSize {
        CGSize(width: tileSize.width - 2 * iconArtworkInset + 2 * focusPlatePadding,
               height: tileSize.height - 2 * iconArtworkInset + 2 * focusPlatePadding)
    }

    public var focusPlatePanelGap: CGFloat { iconSize * 0.12 }

    public var focusPlateToCardGap: CGFloat { focusPlatePanelGap + iconArtworkInset }

    public var cornerRadius: CGFloat { focusPlateRadius + focusPlateToCardGap }

    public var cardHorizontalPadding: CGFloat {
        (focusPlatePadding - tileCellPadding) + focusPlatePanelGap * 1.4
    }

    public var cardSpacing: CGFloat { 10 * scale }

    public var emptyCardWidth: CGFloat { iconSize + 2 * focusPlatePadding }

    /// Small app-icon badge drawn in a preview's corner.
    /// App icon badged on a snapshot: small enough never to compete with the image.
    public var previewBadgeSize: CGFloat { min(28, max(16, iconSize * 0.18)) }

    // Large "peer chip" workspace badge (crew UX): ~0.75x the icon so it reads as
    // an identity element beside the app icons, not a tiny superscript. Kept purely
    // AFFINE (no max floor) so it has no breakpoint inside the width-fit range and
    // the 30/60 two-point fit stays exact; it is naturally generous at small sizes.
    // Presets: 16→14, 24→19.8, 32→25.6, 48→37.2, 96→72.
    public var badgeDiameter: CGFloat { 2.4 + iconSize * 0.725 }
    public var badgeFontSize: CGFloat { max(8, badgeDiameter * 0.58) }
    // Small margin from the card's leading edge to the badge, and the breathing gap
    // from the badge to the first icon. Both kept AFFINE (no max/floor breakpoint)
    // so the badge lane has no kink inside the 30/60 width-fit range and the fit
    // stays exact. Tightened per crew so the badge reads as a compact chip, not a
    // floating disc. margin: 16→3, 48→3.9, 96→5.4; gap: 16→3, 48→4.2, 96→6.
    public var badgeLeadingMargin: CGFloat { 2.5 + iconSize * 0.03 }
    public var badgeToIconGap: CGFloat { 2.4 + iconSize * 0.0375 }
    // Full leading lane the badge occupies (margin + badge + gap). It REPLACES the
    // leading card padding, so the badge lane is the whole left inset. Affine →
    // the 30/60 two-point width fit stays exact.
    public var badgeGutter: CGFloat { badgeLeadingMargin + badgeDiameter + badgeToIconGap }

    public var cardTopPadding: CGFloat { focusPlatePanelGap * 0.8 }
    public var cardBottomPadding: CGFloat { focusPlatePanelGap * 0.8 }

    public var cardHeight: CGFloat {
        cardTopPadding + tileHeight + cardBottomPadding
    }
}
