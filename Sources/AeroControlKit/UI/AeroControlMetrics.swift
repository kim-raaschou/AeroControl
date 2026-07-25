import CoreGraphics

public struct AeroControlMetrics: Equatable, Sendable {
    public static let defaultIconSize: CGFloat = 48

    public let iconSize: CGFloat

    public init(iconSize: CGFloat) {
        self.iconSize = Self.sanitizedIconSize(iconSize)
    }

    public static func sanitizedIconSize(_ value: CGFloat) -> CGFloat {
        (value.isFinite && value > 0) ? value : defaultIconSize
    }

    private static let minTextSize: CGFloat = 7

    private var scale: CGFloat { iconSize / Self.defaultIconSize }

    public var tileCellPadding: CGFloat { 2 * scale }

    public var tileHeight: CGFloat {
        iconSize + 2 * tileCellPadding
    }

    public var appRowSpacing: CGFloat { 8 * scale }

    public var focusPlatePadding: CGFloat { max(Self.minPlatePadding, iconSize * Self.platePaddingFraction) }

    private static let minPlatePadding: CGFloat = 3

    private static let platePaddingFraction: CGFloat = 0.05

    public static var focusPlateFloorIconSize: CGFloat { minPlatePadding / platePaddingFraction }

    private var iconArtworkInset: CGFloat { iconSize * 0.083 }

    public var iconArtworkRadius: CGFloat { (iconSize - 2 * iconArtworkInset) * 0.22 }

    public var focusPlateRadius: CGFloat { iconArtworkRadius + focusPlatePadding }

    public var focusPlateSize: CGFloat { iconSize - 2 * iconArtworkInset + 2 * focusPlatePadding }

    public var focusPlatePanelGap: CGFloat { iconSize * 0.12 }

    public var focusPlateToCardGap: CGFloat { focusPlatePanelGap + iconArtworkInset }

    public var cornerRadius: CGFloat { focusPlateRadius + focusPlateToCardGap }

    public var cardHorizontalPadding: CGFloat {
        (focusPlatePadding - tileCellPadding) + focusPlatePanelGap * 1.4
    }

    public var cardSpacing: CGFloat { 10 * scale }

    public var emptyCardWidth: CGFloat { iconSize + 2 * focusPlatePadding }

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
