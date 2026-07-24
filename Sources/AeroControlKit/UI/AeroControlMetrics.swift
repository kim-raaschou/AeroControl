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

    public var badgeFontSize: CGFloat { max(9, iconSize * 0.20) }
    public var badgePaddingH: CGFloat { 2.5 * scale }
    public var badgePaddingV: CGFloat { 1.5 * scale }
    public var badgeInset: CGFloat { 8 * scale }
    public var badgeMaxWidth: CGFloat { iconSize * 0.95 }

    public var cardTopPadding: CGFloat { focusPlatePanelGap * 0.8 }
    public var cardBottomPadding: CGFloat { focusPlatePanelGap * 0.8 }

    public var cardHeight: CGFloat {
        cardTopPadding + tileHeight + cardBottomPadding
    }
}
