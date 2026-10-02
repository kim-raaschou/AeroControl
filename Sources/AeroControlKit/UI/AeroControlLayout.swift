import Common
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

    /// The room inside a card for its tiles: below the badge lane and its gap, inside the padding.
    public static func innerSize(of card: CGSize) -> CGSize {
        CGSize(width: card.width - 2 * cardPadding, height: card.height - cardChrome)
    }

    /// A card's tiles as drawn: `TilePacker` at the largest picture height that fits `inner`,
    /// with `caption` under each tile (the caption lane while filtering, nothing on the map).
    /// Each card on its own: every cell is the same size, and a card fills its cell with what
    /// it has. One height for the whole screen was tried on 2026-09-30 and dropped the same
    /// day: a single six-window workspace shrank every picture on the map to a stamp.
    public static func packTiles(ratios: [CGFloat], inner: CGSize, gap: CGFloat = tileSpacing, caption: CGFloat) -> TilePacker.Packed {
        let height = TilePacker.packHeight(ratios: ratios, width: inner.width, height: inner.height,
                                           gap: gap, caption: caption, scales: nil)
        return TilePacker.packRows(ratios: ratios, tileHeight: max(1, height), width: inner.width,
                                   gap: gap, caption: caption, scales: nil)
    }

    /// The gap between packed tiles: the gap AeroSpace keeps between windows, at the card's
    /// scale, so a card that packs (an accordion, a subset, a tree the sizes did not decide)
    /// reads as the same screen as a card that draws its tree. Never under 2 points, so tiles
    /// never touch. `tileSpacing` when the overview could not read the gap or the screen.
    public static func tileGap(innerGap: CGFloat?, screen: CGSize?, inner: CGSize) -> CGFloat {
        guard let innerGap, let screen, screen.width > 0 else { return tileSpacing }
        return max(2, innerGap * AeroControlMetrics.fit(screen, into: inner).width / screen.width)
    }

    /// The workspace drawn as AeroSpace lays it out. Exact when AeroSpace said where its layout
    /// put every tiled window (`WindowInfo.layoutRect`, the owner's branch): each at that place, at
    /// the size the window server reports (an app with a minimum size overflows its slot, as on
    /// the screen), in the screen's coordinates scaled into `inner` and centred. Otherwise
    /// the tree read from the windows' sizes and the root's axis (`WorkspaceTree`), at the same
    /// scale. Floating and fullscreen windows are not in either; they lie over it as `ghosts`,
    /// at their own scale, centred, since where a float lies is not readable, and the card draws
    /// them faint for that reason. Nil when a size is missing, the root is an accordion of two or
    /// more without rects, the screen is unknown, or the sizes do not force a tree; the card then
    /// packs tiles. `rows` are the windows by top edge and then the ghosts, for ↑/↓.
    public static func treeLayout(windows: [WindowInfo], sizes: [Int: CGSize], rootLayout: String, screen: CGRect?,
                                  gap: CGFloat?, inner: CGSize) -> (frames: [Int: CGRect], rows: [[Int]], ghosts: Set<Int>, exact: Bool)? {
        let ghosts = windows.filter { $0.isFloating || $0.isFullscreen }.map(\.windowId)
        let tiled = windows.filter { !ghosts.contains($0.windowId) }
        guard windows.count >= 2, !tiled.isEmpty, ghosts.allSatisfy({ sizes[$0] != nil }), inner.width > 0, inner.height > 0, let screen else { return nil }
        let fitted = AeroControlMetrics.fit(screen.size, into: inner)
        let box = CGRect(origin: tileOrigin(packed: fitted, inner: inner), size: fitted)
        let scale = fitted.width / screen.width
        var frames: [Int: CGRect] = [:]
        // AeroSpace's own rects, when every tiled window has one and they tile: rects that overlap
        // are an accordion's, and a map of them would show only the front one, so those pack.
        let rects = tiled.compactMap(\.layoutRect)
        let exact = rects.count == tiled.count && !rects.indices.contains { i in
            rects.indices.contains { j in j > i && rects[i].intersection(rects[j]).width > 2 && rects[i].intersection(rects[j]).height > 2 }
        }
        if !exact, rects.count == tiled.count { return nil }
        if exact {
            // Where AeroSpace put the window, and as big as the app made it: a window with a minimum
            // size refuses AeroSpace's rect and stands over its neighbour on the screen, so here too.
            for window in tiled {
                let r = window.layoutRect!
                let size = sizes[window.windowId] ?? r.size
                frames[window.windowId] = CGRect(x: box.minX + (r.minX - screen.minX) * scale, y: box.minY + (r.minY - screen.minY) * scale,
                                                 width: size.width * scale, height: size.height * scale)
            }
        } else {
            guard let (tree, measured) = tree(of: windows, sizes: sizes, rootLayout: rootLayout, screen: screen) else { return nil }
            frames = WorkspaceTree.frames(of: tree, windows: measured, screen: screen.size, in: box, gap: gap)
        }
        let byTop = Dictionary(grouping: frames, by: { $0.value.minY.rounded() })
        var rows = byTop.keys.sorted().map { top in byTop[top]!.sorted { $0.value.minX < $1.value.minX }.map(\.key) }
        for id in ghosts {
            let size = CGSize(width: min(box.width, sizes[id]!.width * scale), height: min(box.height, sizes[id]!.height * scale))
            frames[id] = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
        }
        if !ghosts.isEmpty { rows.append(ghosts) }
        return (frames, rows, Set(ghosts), exact)
    }

    /// The tiling tree of a workspace's tiled windows, and the windows it was read from; nil
    /// when a size is missing, the root is an accordion of two or more, or the sizes do not
    /// force a tree. Floating and fullscreen windows are left out.
    private static func tree(of windows: [WindowInfo], sizes: [Int: CGSize], rootLayout: String, screen: CGRect)
        -> (WorkspaceTree.Node, [WorkspaceTree.Window])? {
        let tiled = windows.filter { !$0.isFloating && !$0.isFullscreen }
        let measured = tiled.compactMap { w in sizes[w.windowId].map { WorkspaceTree.Window(id: w.windowId, size: $0) } }
        guard !tiled.isEmpty, measured.count == tiled.count,
              let axis = WorkspaceTree.Axis(rootLayout: rootLayout) ?? (tiled.count == 1 ? .horizontal : nil),
              let tree = WorkspaceTree.reconstruct(windows: measured, root: axis, area: screen.size) else { return nil }
        return (tree, measured)
    }

    /// One workspace in the strip: its place on the unrolled row, where each window is drawn
    /// inside the card's picture area, and which of those belong to other apps.
    public struct StripCard: Equatable, Sendable {
        public let workspace: String
        public let span: AppStripModel.Span
        public let frames: [Int: CGRect]
        public let others: Set<Int>
        /// The tree was read from sizes rather than AeroSpace's rects, so its places may be swapped.
        public let orderUnknown: Bool
    }

    public struct StripLayout: Equatable, Sendable {
        /// The cards' shared height, the map card's chrome included.
        public let height: CGFloat
        /// The height of the box the pictures fill: the card less its chrome.
        public let inner: CGFloat
        /// The unrolled row, gaps included.
        public let width: CGFloat
        public let cards: [StripCard]

        /// Whether the row is a ring in a view this wide: from `carouselFrom` cards, or when it does not fit.
        public func runsRound(in viewWidth: CGFloat) -> Bool {
            cards.count >= carouselFrom || width > viewWidth
        }

        /// The box a card's pictures fill, which its frames are in.
        public func innerSize(of card: StripCard) -> CGSize {
            CGSize(width: card.span.width - 2 * cardPadding, height: inner)
        }
    }

    /// The strip as krn.overview lays it out, in the map's cards: one card per workspace holding
    /// the app, its pictures in its screen's shape at one height (`AppStripModel.cardHeight`)
    /// inside the map card's padding and badge lane, mirroring the workspace as the
    /// map does — AeroSpace's rects, or the tree read from sizes — with the other apps' windows
    /// marked to be drawn faint. A card whose layout cannot be read packs only the app's
    /// windows in it, each at its own shape.
    public static func stripLayout(groups: [WorkspaceInfo], bundleId: String, sizes: [Int: CGSize], screens: [Int: CGRect],
                                   fallbackScreen: CGRect, gap: CGFloat?, viewWidth: CGFloat, panelHeight: CGFloat) -> StripLayout {
        let areas = groups.map { screens[$0.screenIndex] ?? fallbackScreen }
        let aspects = areas.map { $0.width / max(1, $0.height) }
        let height = AppStripModel.cardHeight(width: viewWidth - 2 * cardPadding * CGFloat(groups.count), gaps: cardGap * CGFloat(max(0, groups.count - 1)),
                                              sumAspect: aspects.reduce(0, +), panelHeight: panelHeight)
        var x: CGFloat = 0
        var cards: [StripCard] = []
        for (g, workspace) in groups.enumerated() {
            if g > 0 { x += cardGap }
            let size = CGSize(width: (height * aspects[g]).rounded(), height: height)
            let ours = workspace.windows.filter { $0.bundleId == bundleId }
            var frames: [Int: CGRect] = [:], others: Set<Int> = [], orderUnknown = false
            if let mirror = treeLayout(windows: workspace.windows, sizes: sizes, rootLayout: workspace.rootLayout,
                                       screen: areas[g], gap: gap, inner: size) {
                frames = mirror.frames
                others = Set(workspace.windows.map(\.windowId)).subtracting(ours.map(\.windowId))
                orderUnknown = !mirror.exact
            } else {
                let ratios = ratios(of: ours, sizes: sizes, fallback: aspects[g])
                let gapHere = tileGap(innerGap: gap, screen: areas[g].size, inner: size)
                let packed = packTiles(ratios: ratios, inner: size, gap: gapHere, caption: 0)
                let origin = tileOrigin(packed: CGSize(width: packed.width, height: packed.height), inner: size)
                for (i, window) in ours.enumerated() {
                    let t = packed.tiles[i]
                    frames[window.windowId] = CGRect(x: origin.x + t.x, y: origin.y + t.y, width: t.width, height: t.height)
                }
            }
            let outer = size.width + 2 * cardPadding
            cards.append(StripCard(workspace: workspace.name, span: AppStripModel.Span(x: x, width: outer), frames: frames, others: others,
                                   orderUnknown: orderUnknown))
            x += outer
        }
        return StripLayout(height: height + cardChrome, inner: height, width: x, cards: cards)
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

    /// The gap AeroSpace keeps between windows, read once for the overview: the median of what
    /// every workspace shows — from AeroSpace's rects, else from a nested container's sizes. It
    /// is one setting, so any workspace that shows it speaks for all, and an accordion or a flat
    /// card still draws it. Nil when no workspace shows it.
    public static func innerGap(workspaces: [WorkspaceInfo], sizes: [Int: CGSize], screens: [Int: CGRect]) -> CGFloat? {
        let gaps = workspaces.compactMap { ws -> CGFloat? in
            if let gap = rectGap(of: ws.windows) { return gap }
            guard let screen = screens[ws.screenIndex],
                  let (tree, measured) = tree(of: ws.windows, sizes: sizes, rootLayout: ws.rootLayout, screen: screen)
            else { return nil }
            return WorkspaceTree.innerGap(of: tree, windows: measured)
        }.sorted()
        return gaps.isEmpty ? nil : gaps[gaps.count / 2]
    }

    /// AeroSpace's gap, read from its rects: the narrowest space between two tiled windows side
    /// by side or one above the other. Nil without two such — an accordion stacks its windows
    /// on one another, and a workspace of flat tiles has no nested column for the sizes to tell.
    static func rectGap(of windows: [WindowInfo]) -> CGFloat? {
        let rects = windows.filter { !$0.isFloating && !$0.isFullscreen }.compactMap(\.layoutRect)
        return rects.flatMap { a in rects.compactMap { b -> CGFloat? in
            if b.minX >= a.maxX, b.minY < a.maxY, a.minY < b.maxY { return b.minX - a.maxX }
            if b.minY >= a.maxY, b.minX < a.maxX, a.minX < b.maxX { return b.minY - a.maxY }
            return nil
        } }.min()
    }

    /// The box pictures are first taken to fit, in pixels: a strip card at its largest — half the
    /// panel high, in the screen's shape — which holds every window the map draws as well. A tile
    /// that draws one larger asks for it again at its size (`OverviewStore.wantPicture`).
    public static func captureSize(available: CGSize, backingScale: CGFloat) -> CGSize {
        let height = (available.height * usableScreenFraction * 0.5).rounded(.up)
        return CGSize(width: (height * screenRatio(for: available) * backingScale).rounded(.up), height: (height * backingScale).rounded(.up))
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
