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

    /// Horizontal gap between app icons within a card's row.
    public var appRowSpacing: CGFloat { 8 * scale }

    // MARK: - Focus plate (selected app) — all proportional to iconSize

    /// Gap between the focused icon's visible artwork and the edge of its selection
    /// plate — a tight, even hug like the native Cmd-Tab highlight. Scales with the
    /// icon but never drops below a legibility floor, so the focus ring stays visible
    /// even at small icon sizes (mirrors the text `minTextSize` floor).
    public var focusPlatePadding: CGFloat { max(Self.minPlatePadding, iconSize * 0.05) }

    /// Smallest on-screen focus-ring width (pt) we allow, so the selection stays
    /// visible when icons are small.
    private static let minPlatePadding: CGFloat = 3

    /// The transparent margin macOS bakes into every app icon (~8.3% per side on the
    /// Tahoe grid). The visible artwork sits inside it, so the selection plate and the
    /// floating marker discount this margin to hug the artwork, not the empty canvas.
    private var iconArtworkInset: CGFloat { iconSize * 0.083 }

    /// The visible artwork's own squircle corner radius (~22% of the artwork width).
    /// The missing-icon placeholder rounds to this too, so it matches a real icon.
    public var iconArtworkRadius: CGFloat { (iconSize - 2 * iconArtworkInset) * 0.22 }

    /// Selection-plate corner radius, kept concentric with the icon artwork per
    /// Apple's Tahoe concentric-corner rule: plateRadius = artworkRadius + padding.
    /// This nests the plate around the rounded icon instead of boxing it.
    public var focusPlateRadius: CGFloat { iconArtworkRadius + focusPlatePadding }

    /// The selection plate's side: the visible artwork plus a tight even hug on all
    /// sides (the icon's transparent margin is discounted), so the plate clings to the
    /// artwork rather than floating around the full icon canvas.
    public var focusPlateSize: CGFloat { iconSize - 2 * iconArtworkInset + 2 * focusPlatePadding }

    /// Air between the selection plate's edge and the card's outer panel edge. Also
    /// proportional to iconSize, so the breathing room scales with the icons.
    public var focusPlatePanelGap: CGFloat { iconSize * 0.12 }

    /// The true distance from the selection plate's edge to the card's outer edge:
    /// the panel gap plus the icon's transparent artwork margin (the plate hugs the
    /// *artwork*, so the empty margin also sits between the plate and the card edge).
    /// Used to keep the card corner concentric with the plate.
    public var focusPlateToCardGap: CGFloat { focusPlatePanelGap + iconArtworkInset }

    /// Corner radius for cards / empty tiles / focus border. Kept concentric with the
    /// selection plate per Apple's Tahoe concentric-corner rule — cardRadius =
    /// plateRadius + (plate→card gap) — so the workspace card, the focus plate, and the
    /// icon artwork all share one nested corner layout (icon ⊂ plate ⊂ card) at every
    /// icon size, instead of the card using an independent, flatter radius.
    public var cornerRadius: CGFloat { focusPlateRadius + focusPlateToCardGap }

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
    /// Inset of the workspace-name badge from the card's top-leading corner. Clears the
    /// rounded corner's arc — the arc intrudes ~0.293·radius along the diagonal (that's
    /// `1 − 1/√2`), so the badge is pushed in by that plus a small base gap, keeping it
    /// off (and unclipped by) the now-concentric, more-rounded corner at every size.
    public var badgeInset: CGFloat { 2 * scale + cornerRadius * 0.293 }

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
