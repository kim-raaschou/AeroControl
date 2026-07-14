import CoreGraphics

/// Fixed layout metrics for the AeroControl top panel, derived from the icon size.
///
/// Everything is a pure function of `iconSize`, so the SwiftUI panel, the AppKit
/// window, and the gap controller all agree on the panel's height without any
/// runtime measurement. Chrome constants mirror the paddings/labels used by
/// `AeroControlAppTile` / `AeroControlWorkspaceCard` / `AeroControlPanel`.
public struct AeroControlMetrics: Equatable, Sendable {
    /// Fallback used when a requested size is missing, invalid, or non-positive.
    public static let defaultIconSize: CGFloat = 48

    public let iconSize: CGFloat

    public init(iconSize: CGFloat) {
        self.iconSize = Self.sanitizedIconSize(iconSize)
    }

    /// Accepts any positive, finite icon size (no upper/lower bound). Non-positive
    /// or non-finite values fall back to `defaultIconSize` so layout stays valid.
    public static func sanitizedIconSize(_ value: CGFloat) -> CGFloat {
        (value.isFinite && value > 0) ? value : defaultIconSize
    }

    // MARK: - Reference design & scale
    //
    // Every layout detail below is expressed as the value that looked right at the
    // *reference* icon size (`defaultIconSize`, 48pt), multiplied by `scale`. So the
    // only literals are genuine design decisions ("radius is 12, badge font is 9 at
    // 48pt"), not opaque tuning ratios — the panel simply scales as one coherent unit.
    // Text has a legibility floor; corner radius is capped so large icons don't
    // over-round.

    /// Smallest on-screen font (pt) we allow, so labels stay readable on tiny icons.
    private static let minTextSize: CGFloat = 7

    /// The current icon size relative to the reference. 1.0 at `defaultIconSize`.
    private var scale: CGFloat { iconSize / Self.defaultIconSize }

    // MARK: - Tile (single app icon)

    /// Padding around the icon inside a tile (matches `AeroControlAppTile`).
    public var tileCellPadding: CGFloat { 2 * scale }

    /// The tile is just the icon plus its padding — the app name no longer sits in
    /// the tile flow (it is drawn as a bottom overlay only for the focused app).
    public var tileHeight: CGFloat {
        iconSize + 2 * tileCellPadding
    }

    // MARK: - Proportional detail metrics (all = reference value × scale)

    /// Corner radius for cards / empty tiles / focus border. Scales down for small
    /// icons but never exceeds its reference (so large icons don't over-round).
    public var cornerRadius: CGFloat { 12 * min(1, scale) }

    /// Horizontal gap between app icons within a card's row.
    public var appRowSpacing: CGFloat { 8 * scale }

    // MARK: - Focus plate (selected app) — all proportional to iconSize

    /// Gap between the focused icon and the edge of its selection plate. Proportional
    /// to the icon, so the plate grows/shrinks with the icon size.
    public var focusPlatePadding: CGFloat { iconSize * 0.12 }

    /// The selection plate's side: the icon plus its padding on all sides. Scales
    /// directly with iconSize.
    public var focusPlateSize: CGFloat { iconSize + 2 * focusPlatePadding }

    /// Air between the selection plate's edge and the card's outer panel edge. Also
    /// proportional to iconSize, so the breathing room scales with the icons.
    public var focusPlatePanelGap: CGFloat { iconSize * 0.12 }

    /// Horizontal padding inside a card, around the icon row. Sized so the focus
    /// plate (which overflows the tile) still leaves `focusPlatePanelGap` of air to
    /// the panel edge: card padding = plate overflow beyond the tile + the panel gap.
    public var cardHorizontalPadding: CGFloat {
        (focusPlatePadding - tileCellPadding) + focusPlatePanelGap
    }

    /// Horizontal gap between adjacent workspace cards in the strip. Scales with
    /// the icon size so the whole row width stays linear in `iconSize`.
    public var cardSpacing: CGFloat { 8 * scale }

    /// Width of an empty workspace card. Matches the total width of a card holding
    /// a single app icon (one tile plus the card's horizontal padding), so empty
    /// and non-empty workspaces share the exact same box design across the strip.
    public var emptyCardWidth: CGFloat { tileHeight + 2 * cardHorizontalPadding }

    /// Workspace-name badge: font, inner padding, and corner inset.
    public var badgeFontSize: CGFloat { max(Self.minTextSize, 9 * scale) }
    public var badgePaddingH: CGFloat { 6 * scale }
    public var badgePaddingV: CGFloat { 2 * scale }
    public var badgeInset: CGFloat { 2 * scale }

    // MARK: - Card (one workspace)

    /// The workspace name is a badge overlay (no header row), so the card is just the
    /// icon row plus vertical padding. Kept equal to the horizontal padding so the
    /// focused app's selection plate (which extends beyond its tile) has the same
    /// breathing room on all four sides.
    public var cardTopPadding: CGFloat { cardHorizontalPadding }
    public var cardBottomPadding: CGFloat { cardHorizontalPadding }

    public var cardHeight: CGFloat {
        cardTopPadding + tileHeight + cardBottomPadding
    }
}
