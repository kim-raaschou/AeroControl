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
        let ghosts = windows.filter { $0.isFloating || $0.isFullscreen }.map(\.windowId)
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

        /// Whether the row is a ring in a view this wide: from `carouselFrom` cards, or when it does not fit.
        public func runsRound(in viewWidth: CGFloat) -> Bool {
            cards.count >= carouselFrom || width > viewWidth
        }
    }

    /// The strip as krn.overview lays it out, in the map's cards: one card per workspace holding
    /// the app, its pictures in its screen's shape at one height (`AppStripModel.cardHeight`)
    /// inside the map card's padding and badge lane, mirroring the workspace as the map does — from
    /// AeroSpace's rects — with the other apps' windows marked to be drawn faint. A card whose
    /// layout cannot be read packs only the app's windows, each at its own shape, in one row: the
    /// strip is a row of choices, and two wide windows stacked read as one window over another.
    /// The packed cards share one picture height, the tightest row's, and each hugs its row: a
    /// choice is not bigger for being alone on its workspace, and no card is a screen's width
    /// round a small picture. When no card mirrors a screen, the strip is only as tall as that row.
    public static func stripLayout(groups: [WorkspaceInfo], bundleId: String, sizes: [Int: CGSize], screens: [Int: CGRect],
                                   fallbackScreen: CGRect, viewWidth: CGFloat, panelHeight: CGFloat) -> StripLayout {
        let areas = groups.map { screens[$0.screenIndex] ?? fallbackScreen }
        let aspects = areas.map { $0.width / max(1, $0.height) }
        let full = AppStripModel.cardHeight(width: viewWidth - 2 * cardPadding * CGFloat(groups.count), gaps: cardGap * CGFloat(max(0, groups.count - 1)),
                                            sumAspect: aspects.reduce(0, +), panelHeight: panelHeight)
        let widths = aspects.map { (full * $0).rounded() }
        let ours = groups.map { ws in ws.windows.filter { $0.bundleId == bundleId } }
        let shapes = groups.indices.map { ratios(of: ours[$0], sizes: sizes, fallback: aspects[$0]) }
        let gaps = groups.indices.map { packedGap(screen: areas[$0].size, inner: CGSize(width: widths[$0], height: full)) }
        let mirrors = groups.indices.map { treeLayout(windows: groups[$0].windows, sizes: sizes, screen: areas[$0], inner: CGSize(width: widths[$0], height: full)) }
        let row = groups.indices.filter { mirrors[$0] == nil }.map { g in
            min(full, ((widths[g] - gaps[g] * CGFloat(max(0, ours[g].count - 1))) / max(0.01, shapes[g].reduce(0, +))).rounded(.down))
        }.min() ?? full
        let height = mirrors.contains { $0 != nil } ? full : max(1, row)
        var x: CGFloat = 0, cards: [StripCard] = []
        for g in groups.indices {
            if g > 0 { x += cardGap }
            var frames: [Int: CGRect] = [:], others: Set<Int> = [], width = widths[g]
            if let mirror = mirrors[g] {
                frames = mirror.frames
                others = Set(groups[g].windows.map(\.windowId)).subtracting(ours[g].map(\.windowId))
            } else {
                let packed = TilePacker.packRows(ratios: shapes[g], tileHeight: max(1, row), width: widths[g], gap: gaps[g], caption: 0)
                let top = tileOrigin(packed: CGSize(width: packed.width, height: packed.height), inner: CGSize(width: packed.width, height: height)).y
                frames = Dictionary(uniqueKeysWithValues: zip(ours[g].map(\.windowId), packed.tiles.map {
                    CGRect(x: $0.x, y: top + $0.y, width: $0.width, height: $0.height) }))
                width = packed.width
            }
            cards.append(StripCard(workspace: groups[g].name, span: AppStripModel.Span(x: x, width: width + 2 * cardPadding), frames: frames, others: others))
            x += width + 2 * cardPadding
        }
        return StripLayout(height: height + cardChrome, width: x, cards: cards)
    }

    /// From this many workspaces the strip is always a carousel: the marked card in the middle,
    /// the row running round, every step turning the wheel. With fewer, a ring only centres one
    /// card and leaves the view half empty, so the row stands still when it fits.
    public static let carouselFrom = 3

    /// One card where the strip draws it: which card, which time round the ring (`copy`), its
    /// left edge in the view, and whether it is seen or only stands by just out of sight.
    public struct StripPlacement: Hashable, Sendable {
        public let card: Int
        public let copy: Int
        public let x: CGFloat
        public var shown = true
        /// The view's identity: the same card the same time round, wherever the ring has turned it.
        public var identity: String { "\(card)#\(copy)" }
    }

    /// Where the strip's cards stand. A row that fits, under `carouselFrom` cards, stands still
    /// and centred. Otherwise it is a ring turned so the card holding `centre` — the window the
    /// keys put the marking on — is in the middle, `turns` times round: the cards repeat every
    /// ring's width, and each is shown where it shows — once when it shows whole, else every
    /// piece the edges leave, so the card across the ring is cut by both and the row is whole
    /// either side. Counting the turns keeps a copy's place continuous: past the last card the
    /// ring moves on one card the same way, and nothing jumps back across. The copies a card
    /// beyond either edge are placed too, unseen, so a turn slides them in rather than making
    /// them appear: nothing comes or goes at the edges while the ring moves.
    public static func stripPlacements(_ layout: StripLayout, centre: Int?, turns: Int, viewWidth: CGFloat) -> [StripPlacement] {
        guard let first = layout.cards.first else { return [] }
        guard layout.runsRound(in: viewWidth) else {
            let still = (viewWidth / 2 - layout.width / 2 - first.span.x).rounded()
            return layout.cards.indices.map { StripPlacement(card: $0, copy: 0, x: layout.cards[$0].span.x + still) }
        }
        let ring = layout.width + cardGap
        // The card's middle, not the window's: stepping between windows of one workspace moves the
        // marking and leaves the row; the row turns a whole card at a time.
        let held = layout.cards.first { card in centre.map { card.frames[$0] != nil } ?? false } ?? first
        let offset = viewWidth / 2 - (held.span.x + held.span.width / 2 + CGFloat(turns) * ring)
        let margin = (layout.cards.map(\.span.width).max() ?? 0) + cardGap     // one card beyond each edge
        return layout.cards.indices.flatMap { g -> [StripPlacement] in
            let span = layout.cards[g].span
            let lowest = Int(((-margin - offset - span.x - span.width) / ring).rounded(.down))
            let highest = Int(((viewWidth + margin - offset - span.x) / ring).rounded(.up))
            let near = (lowest...highest).map { StripPlacement(card: g, copy: $0, x: (span.x + CGFloat($0) * ring + offset).rounded()) }
                .filter { $0.x + span.width > -margin && $0.x < viewWidth + margin }
            let seen = near.filter { $0.x + span.width > 0 && $0.x < viewWidth }
            let whole = seen.filter { $0.x >= 0 && $0.x + span.width <= viewWidth }
            let shown = whole.isEmpty ? seen : [whole.min { abs($0.x + span.width / 2 - viewWidth / 2) < abs($1.x + span.width / 2 - viewWidth / 2) }!]
            return near.map { StripPlacement(card: $0.card, copy: $0.copy, x: $0.x, shown: shown.contains($0)) }
        }
    }

    /// The box pictures are first taken to fit, in pixels: a strip card at its largest — half the
    /// panel high, in the screen's shape — which holds every window the map draws as well. A tile
    /// that draws one larger asks for it again at its size (`OverviewStore.wantPicture`).
    public static func captureSize(available: CGSize, backingScale: CGFloat) -> CGSize {
        let height = (available.height * usableScreenFraction * 0.5).rounded(.up)
        return CGSize(width: (height * screenRatio(for: available) * backingScale).rounded(.up), height: (height * backingScale).rounded(.up))
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
