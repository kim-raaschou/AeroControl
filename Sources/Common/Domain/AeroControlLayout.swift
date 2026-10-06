import CoreGraphics

/// The overview's layout constants, and the two pure engines wired to them: `CardGrid`
/// places the workspace cards (one identical, screen-shaped cell each, in a lattice),
/// `TilePacker` places the windows inside a card (each at its own shape, one shared picture
/// height inside the card, as large as its cell allows). All unit-tested.
public enum AeroControlLayout {
    public static let usableScreenFraction: CGFloat = 0.94
    public static let cardGap: CGFloat = 24
    public static let tileSpacing: CGFloat = 14
    public static let cardPadding: CGFloat = 18
    public static let cardRadius: CGFloat = 18
    /// Vertical room reserved at the top of a card for the workspace badge.
    public static let badgeLane: CGFloat = 44
    /// Diameter of the workspace badge in the card header.
    public static let badgeSize: CGFloat = 24
    /// While a filter is up each tile carries a caption above its picture: a title line and
    /// the gap to the picture. Both the tile and `usedHeight` budget for it from here.
    public static let captionTitleHeight: CGFloat = 32
    public static let captionGap: CGFloat = 6
    public static let captionLane: CGFloat = captionTitleHeight + captionGap

    /// Width / height of a window nothing is known about yet: the screen's own shape.
    public static func screenRatio(for available: CGSize) -> CGFloat {
        available.height > 0 ? available.width / available.height : 1.5
    }

    /// Width / height of each window, from its measured size, the screen's when unmeasured.
    public static func ratios(of windows: [WindowInfo], sizes: [Int: CGSize], fallback: CGFloat) -> [CGFloat] {
        windows.map { window in
            guard let size = sizes[window.windowId], size.width > 0, size.height > 0 else { return fallback }
            return size.width / size.height
        }
    }

    /// A card's height that is not pictures: the padding, the badge lane, and the gap
    /// between the badge and the first row of tiles.
    public static let cardChrome: CGFloat = cardPadding + badgeLane + tileSpacing
    /// The room inside a card of `size` for its tiles: below the badge lane and its gap, inside the padding.
    public static func inner(of size: CGSize) -> CGSize { CGSize(width: size.width - 2 * cardPadding, height: size.height - cardChrome) }

    /// The gap between packed tiles, in the screen's points: one constant, scaled to the card like
    /// everything else, so a packed card (an accordion, a filtered subset, a workspace a release
    /// AeroSpace cannot place) reads like a card drawn from AeroSpace's rects. It is an assumption
    /// about the user's `gaps.inner`, the one in the overview; AeroSpace's own rects carry the real
    /// gap, and only they are drawn as a map. `tileSpacing` when the screen is unknown; never
    /// under 2 points, so tiles never touch.
    public static let packedGapOnScreen: CGFloat = 12
    public static func packedGap(screen: CGSize?, inner: CGSize) -> CGFloat {
        guard let screen, screen.width > 0 else { return tileSpacing }
        return max(2, packedGapOnScreen * AeroControlMetrics.fit(screen, into: inner).width / screen.width)
    }

    /// The workspace as AeroSpace laid it out, when it said where (`WindowInfo.layoutRect`, the
    /// owner's AeroSpace branch): each tiled window at that place, at the size the window server
    /// reports (an app with a minimum size overflows its slot, as on the screen), in the screen's
    /// coordinates scaled into `inner` and centred. Floating and fullscreen windows are not in the
    /// layout; they lie over it as `ghosts`, at their own scale, centred, since where a float lies
    /// is not readable, and the card draws them faint for that reason. Nil when a tiled window has
    /// no rect (a release AeroSpace, or a window opened on a hidden workspace before it was next
    /// shown), when the rects overlap (an accordion: only the front one would show), or when the
    /// screen is unknown; the card then packs tiles.
    public static func treeLayout(windows: [WindowInfo], sizes: [Int: CGSize], screen: CGRect?, inner: CGSize)
        -> (frames: [Int: CGRect], ghosts: Set<Int>)? {
        let ghosts = windows.filter { $0.isFloating || $0.isFullscreen || $0.isHidden }.map(\.windowId)
        let tiled = windows.filter { !ghosts.contains($0.windowId) }
        let rects = tiled.compactMap(\.layoutRect)
        guard windows.count >= 2, !tiled.isEmpty, rects.count == tiled.count, inner.width > 0, inner.height > 0, let screen,
              !rects.indices.contains(where: { i in rects.indices.contains { j in
                  j > i && rects[i].intersection(rects[j]).width > 2 && rects[i].intersection(rects[j]).height > 2 } })
        else { return nil }
        let fitted = AeroControlMetrics.fit(screen.size, into: inner)
        let box = CGRect(origin: tileOrigin(packed: fitted, inner: inner), size: fitted)
        let scale = fitted.width / screen.width
        var frames: [Int: CGRect] = [:]
        for window in tiled {
            let r = window.layoutRect!
            let size = sizes[window.windowId] ?? r.size
            frames[window.windowId] = CGRect(x: box.minX + (r.minX - screen.minX) * scale, y: box.minY + (r.minY - screen.minY) * scale,
                                             width: size.width * scale, height: size.height * scale)
        }
        for id in ghosts {
            // A ghost's size is the window server's; without one (no Screen Recording) the screen's box.
            let size = sizes[id].map { CGSize(width: min(box.width, $0.width * scale), height: min(box.height, $0.height * scale)) } ?? box.size
            frames[id] = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
        }
        return (frames, Set(ghosts))
    }

    /// One workspace in the strip: its place on the unrolled row, where each window is drawn
    /// inside the card's picture area, and which of those belong to other apps.
    public struct StripCard: Equatable, Sendable {
        public let workspace: String
        public let span: AppStripModel.Span
        public let frames: [Int: CGRect]
        public let others: Set<Int>
    }

    public struct StripLayout: Equatable, Sendable {
        /// The cards' shared height, the map card's chrome included.
        public let height: CGFloat
        /// The unrolled row, gaps included.
        public let width: CGFloat
        public let cards: [StripCard]

        /// Whether the row slides in a view this wide: only when it does not fit. A row that fits
        /// stands still, so the keys on its cards stay where they are read (krn.overview's rule).
        public func slides(in viewWidth: CGFloat) -> Bool { width > viewWidth }
    }

    /// The strip as krn.overview lays it out, in the map's cards: one card per workspace holding
    /// the app, its pictures in its screen's shape at one height (`AppStripModel.cardHeight`)
    /// inside the map card's padding and badge lane, mirroring the workspace as the map does — from
    /// AeroSpace's rects — with the other apps' windows marked to be drawn faint. A card whose
    /// layout cannot be read packs only the app's windows, each at its own shape, as large as its
    /// box allows, as the map does — two always side by side, never one over the other, which
    /// reads as one window. Every card is its workspace's screen: the strip is a row of
    /// workspaces, and one that does not fit slides workspace by workspace (`slides`).
    public static func stripLayout(groups: [WorkspaceInfo], bundleId: String, sizes: [Int: CGSize], screens: [Int: CGRect],
                                   fallbackScreen: CGRect, viewWidth: CGFloat, panelHeight: CGFloat) -> StripLayout {
        let areas = groups.map { screens[$0.screenIndex] ?? fallbackScreen }
        let aspects = areas.map { $0.width / max(1, $0.height) }
        let full = AppStripModel.cardHeight(view: viewWidth, cards: groups.count, aspect: aspects.reduce(0, +) / CGFloat(max(1, groups.count)),
                                            chrome: 2 * cardPadding + cardGap, panelHeight: panelHeight)
        let widths = aspects.map { (full * $0).rounded() }
        let ours = groups.map { ws in ws.windows.filter { $0.bundleId == bundleId } }
        let shapes = groups.indices.map { ratios(of: ours[$0], sizes: sizes, fallback: aspects[$0]) }
        let gaps = groups.indices.map { packedGap(screen: areas[$0].size, inner: CGSize(width: widths[$0], height: full)) }
        let mirrors = groups.indices.map { treeLayout(windows: groups[$0].windows, sizes: sizes, screen: areas[$0], inner: CGSize(width: widths[$0], height: full)) }
        var x: CGFloat = 0, cards: [StripCard] = []
        for g in groups.indices {
            if g > 0 { x += cardGap }
            var frames: [Int: CGRect] = [:], others: Set<Int> = []
            if let mirror = mirrors[g] {
                frames = mirror.frames
                others = Set(groups[g].windows.map(\.windowId)).subtracting(ours[g].map(\.windowId))
            } else {
                let inner = CGSize(width: widths[g], height: full)
                let side = ((inner.width - gaps[g]) / max(0.01, shapes[g].reduce(0, +))).rounded(.down)
                let th = shapes[g].count == 2 ? min(full, side) : TilePacker.packHeight(ratios: shapes[g], width: inner.width, height: inner.height, gap: gaps[g], caption: 0)
                let packed = TilePacker.packRows(ratios: shapes[g], tileHeight: th, width: inner.width, gap: gaps[g], caption: 0)
                let at = tileOrigin(packed: CGSize(width: packed.width, height: packed.height), inner: inner)
                frames = Dictionary(uniqueKeysWithValues: zip(ours[g].map(\.windowId), packed.tiles.map {
                    CGRect(x: at.x + $0.x, y: at.y + $0.y, width: $0.width, height: $0.height) }))
            }
            cards.append(StripCard(workspace: groups[g].name, span: AppStripModel.Span(x: x, width: widths[g] + 2 * cardPadding), frames: frames, others: others))
            x += widths[g] + 2 * cardPadding
        }
        return StripLayout(height: full + cardChrome, width: x, cards: cards)
    }

    /// One card where the strip draws it: which card, and its left edge in the view.
    public struct StripPlacement: Hashable, Sendable {
        public let card: Int
        public let x: CGFloat
    }

    /// Where the strip's cards stand, in one row. A row that fits stands still and centred. One
    /// that does not slides so the card holding `centre` — the window the keys put the marking
    /// on — is in the middle, but no further than the row's ends: the first card stays at the
    /// left edge and the last at the right, and from the last to the first the row slides back
    /// the whole way. The card's middle, not the window's: stepping between windows of one
    /// workspace moves the marking and leaves the row.
    public static func stripPlacements(_ layout: StripLayout, centre: Int?, viewWidth: CGFloat) -> [StripPlacement] {
        guard let first = layout.cards.first else { return [] }
        let held = layout.cards.first { card in centre.map { card.frames[$0] != nil } ?? false } ?? first
        let wanted = viewWidth / 2 - held.span.x - held.span.width / 2
        let offset = layout.slides(in: viewWidth) ? min(0, max(viewWidth - layout.width, wanted)) : (viewWidth - layout.width) / 2
        return layout.cards.indices.map { StripPlacement(card: $0, x: (layout.cards[$0].span.x + offset).rounded()) }
    }

    /// The box pictures are first taken to fit, in pixels. In the strip: a strip card at its largest,
    /// `AppStripModel.tallest` of the panel high in the screen's shape. On the map: a card's inner box, the most a tile
    /// there draws (a window alone on its card), never more than the strip's. A tile drawn larger,
    /// by a query or the strip taking over, asks for it again at its size (`OverviewStore.wantPicture`).
    public static func captureSize(available: CGSize, backingScale: CGFloat, workspaces: Int, strip: Bool) -> CGSize {
        let height = (available.height * usableScreenFraction * AppStripModel.tallest).rounded(.up)
        var box = CGSize(width: height * screenRatio(for: available), height: height)
        let usable = CGSize(width: available.width * usableScreenFraction, height: available.height * usableScreenFraction)
        let cell = CardGrid.lattice(count: max(1, workspaces), in: usable, cellRatio: screenRatio(for: available), gap: cardGap,
                                    chrome: CGSize(width: 2 * cardPadding, height: cardChrome)).first?.size ?? usable
        if !strip { box = CGSize(width: min(box.width, inner(of: cell).width), height: min(box.height, inner(of: cell).height)) }
        return CGSize(width: (box.width * backingScale).rounded(.up), height: (box.height * backingScale).rounded(.up))
    }

    /// What lies over what when frames overlap: a ghost (a float, a fullscreen window) over
    /// everything, as on the screen; the focused window over its neighbours, since a window that
    /// refused its slot for a minimum size stands over the one beside it, and the one in front on
    /// the screen is the one with focus; the rest as AeroSpace listed them.
    public static func stacking(windowId: Int, focused: Int, ghosts: Set<Int>) -> Double {
        ghosts.contains(windowId) ? 2 : windowId == focused ? 1 : 0
    }

    /// Where a card's packed tiles sit in its inner box: centred both ways, so a card with
    /// fewer windows than the busiest reads as a centred picture and not as a top-heavy box.
    /// Every cell is the same size, so this is what a lattice wants; a block too big for the
    /// box is pinned at its top-left.
    public static func tileOrigin(packed: CGSize, inner: CGSize) -> CGPoint {
        CGPoint(x: max(0, ((inner.width - packed.width) / 2).rounded(.down)),
                y: max(0, ((inner.height - packed.height) / 2).rounded(.down)))
    }

    /// The mark on a card for how AeroSpace lays its workspace out: tiles are a row or a column, an accordion
    /// a stack with one window in front. It says what AeroSpace does with the windows, not where any one is,
    /// which a hidden workspace does not tell. One window gets it too: the layout is how the next one will be
    /// arranged. Nothing for an empty workspace, whose card has no room, or for a layout it does not know.
    public static func layoutSymbol(rootLayout: String, windowCount: Int) -> (name: String, help: String)? {
        guard windowCount >= 1 else { return nil }
        switch rootLayout {
        case "h_tiles": return ("rectangle.split.2x1", "Tiles: windows side by side")
        case "v_tiles": return ("rectangle.split.1x2", "Tiles: windows one above another")
        case "h_accordion", "v_accordion": return ("rectangle.on.rectangle", "Accordion: windows stacked, one in front")
        default: return nil
        }
    }

}
