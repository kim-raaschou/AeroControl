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
        (focusPlatePadding - tileCellPadding) + focusPlatePanelGap
    }

    public var cardSpacing: CGFloat { 8 * scale }

    public var emptyCardWidth: CGFloat { tileHeight + 2 * cardHorizontalPadding }

    public var badgeFontSize: CGFloat { max(Self.minTextSize, 9 * scale) }
    public var badgePaddingH: CGFloat { 6 * scale }
    public var badgePaddingV: CGFloat { 2 * scale }
    public var badgeInset: CGFloat { 2 * scale + cornerRadius * 0.293 }

    public var cardTopPadding: CGFloat { cardHorizontalPadding }
    public var cardBottomPadding: CGFloat { cardHorizontalPadding }

    public var cardHeight: CGFloat {
        cardTopPadding + tileHeight + cardBottomPadding
    }
}
