import CoreGraphics

public enum AeroControlLayout {
    public static let usableScreenFraction: CGFloat = 0.94
    public static let pillLane: CGFloat = 38
    public static let pillGap: CGFloat = 18

    public static func usable(_ available: CGSize) -> CGSize {
        CGSize(width: available.width * usableScreenFraction, height: available.height * usableScreenFraction - pillLane - pillGap)
    }
    public static let cardGap: CGFloat = 24
    public static let tileSpacing: CGFloat = 14
    public static let cardPadding: CGFloat = 18
    public static let cardRadius: CGFloat = 18
    public static let badgeLane: CGFloat = 44
    public static let badgeSize: CGFloat = 24
    public static let captionTitleHeight: CGFloat = 32
    public static let captionGap: CGFloat = 6
    public static let captionLane: CGFloat = captionTitleHeight + captionGap

    public static func screenRatio(for available: CGSize) -> CGFloat {
        available.height > 0 ? available.width / available.height : 1.5
    }

    public static func ratios(of windows: [WindowInfo], sizes: [Int: CGSize], fallback: CGFloat) -> [CGFloat] {
        windows.map { window in
            guard let size = sizes[window.windowId], size.width > 0, size.height > 0 else { return fallback }
            return size.width / size.height
        }
    }

    public static let cardChrome: CGFloat = cardPadding + badgeLane + tileSpacing
    public static func inner(of size: CGSize) -> CGSize { CGSize(width: size.width - 2 * cardPadding, height: size.height - cardChrome) }

    public static let packedGapOnScreen: CGFloat = 12
    public static func packedGap(screen: CGSize?, inner: CGSize) -> CGFloat {
        guard let screen, screen.width > 0 else { return tileSpacing }
        return max(2, packedGapOnScreen * AeroControlMetrics.fit(screen, into: inner).width / screen.width)
    }

    public static func treeLayout(_ workspace: WorkspaceInfo, sizes: [Int: CGSize], screen: CGRect?, inner: CGSize)
        -> (frames: [Int: CGRect], ghosts: Set<Int>)? {
        let windows = workspace.windows
        let ghosts = windows.filter { !$0.isTiled }.map(\.windowId)
        let tiled = windows.filter(\.isTiled)
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
            frames[window.windowId] = CGRect(x: box.minX + (r.minX - screen.minX) * scale, y: box.minY + (r.minY - screen.minY) * scale,
                                             width: r.width * scale, height: r.height * scale)
        }
        for id in ghosts {
            let size = sizes[id].map { CGSize(width: min(box.width, $0.width * scale), height: min(box.height, $0.height * scale)) } ?? box.size
            frames[id] = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
        }
        return (frames, Set(ghosts))
    }

    public struct MapCard: Equatable, Sendable {
        public let workspace: String
        public let frame: CGRect
        public let frames: [Int: CGRect]
        public let ghosts: Set<Int>

        public var grid: GridWalk.Card {
            (frame, frames.mapValues { $0.offsetBy(dx: frame.minX + cardPadding, dy: frame.minY + cardChrome - cardPadding) })
        }
    }

    public static func mapLayout(workspaces: [WorkspaceInfo], sizes: [Int: CGSize], screens: [Int: CGRect], available: CGSize, usable: CGSize,
                                 filtering: Bool) -> [MapCard] {
        let cells = CardGrid.lattice(count: workspaces.count, in: usable, cellRatio: screenRatio(for: available), gap: cardGap,
                                     chrome: CGSize(width: 2 * cardPadding, height: cardChrome))
        return zip(workspaces, cells).enumerated().map { i, pair in
            let (ws, cell) = pair, screen = screens[ws.screenIndex], inner = inner(of: cell.size)
            let laid = filtering ? nil : treeLayout(ws, sizes: sizes, screen: screen, inner: inner)
            let placed = laid ?? packed(ws.windows, sizes: sizes, screen: screen, inner: inner, caption: filtering ? captionLane : 0)
            let standIn = [-1 - i: CGRect(origin: .zero, size: inner)].filter { _ in placed.frames.isEmpty }
            return MapCard(workspace: ws.name, frame: cell, frames: placed.frames.merging(standIn) { a, _ in a }, ghosts: placed.ghosts)
        }
    }

    static func packed(_ windows: [WindowInfo], sizes: [Int: CGSize], screen: CGRect?, inner: CGSize, caption: CGFloat) -> (frames: [Int: CGRect], ghosts: Set<Int>) {
        let ratios = ratios(of: windows, sizes: sizes, fallback: screenRatio(for: screen?.size ?? inner))
        let gap = packedGap(screen: screen?.size, inner: inner)
        let height = TilePacker.packHeight(ratios: ratios, width: inner.width, height: inner.height, gap: gap, caption: caption)
        let packed = TilePacker.packRows(ratios: ratios, tileHeight: max(1, height), width: inner.width, gap: gap, caption: caption)
        let origin = tileOrigin(packed: CGSize(width: packed.width, height: packed.height), inner: inner)
        let frames = Dictionary(zip(windows.map(\.windowId), packed.tiles.map { CGRect(x: origin.x + $0.x, y: origin.y + $0.y, width: $0.width, height: $0.height) }),
                                uniquingKeysWith: { _, b in b })
        return (frames, [])
    }

    public struct StripCard: Equatable, Sendable {
        public let workspace: String
        public let span: StripGeometry.Span
        public let frames: [Int: CGRect]
        public let others: Set<Int>
    }

    public struct StripLayout: Equatable, Sendable {
        public let height: CGFloat
        public let width: CGFloat
        public let cards: [StripCard]

        public func slides(in viewWidth: CGFloat) -> Bool { width > viewWidth }

        public var grid: [GridWalk.Card] {
            cards.map { c in (CGRect(x: c.span.x, y: 0, width: c.span.width, height: height),
                              c.frames.filter { !c.others.contains($0.key) }.mapValues { $0.offsetBy(dx: c.span.x + cardPadding, dy: 0) }) }
        }
    }

    public static func stripLayout(groups: [WorkspaceInfo], bundleId: String, sizes: [Int: CGSize], screens: [Int: CGRect],
                                   fallbackScreen: CGRect, viewWidth: CGFloat, panelHeight: CGFloat) -> StripLayout {
        let areas = groups.map { screens[$0.screenIndex] ?? fallbackScreen }
        let aspects = areas.map { $0.width / max(1, $0.height) }
        let full = StripGeometry.cardHeight(view: viewWidth, cards: groups.count, aspect: aspects.reduce(0, +) / CGFloat(max(1, groups.count)),
                                            chrome: 2 * cardPadding + cardGap, panelHeight: panelHeight)
        let widths = aspects.map { (full * $0).rounded() }
        let ours = groups.map { ws in ws.windows.filter { $0.bundleId == bundleId } }
        let shapes = groups.indices.map { ratios(of: ours[$0], sizes: sizes, fallback: aspects[$0]) }
        let gaps = groups.indices.map { packedGap(screen: areas[$0].size, inner: CGSize(width: widths[$0], height: full)) }
        let mirrors = groups.indices.map { treeLayout(groups[$0], sizes: sizes, screen: areas[$0], inner: CGSize(width: widths[$0], height: full)) }
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
            cards.append(StripCard(workspace: groups[g].name, span: StripGeometry.Span(x: x, width: widths[g] + 2 * cardPadding), frames: frames, others: others))
            x += widths[g] + 2 * cardPadding
        }
        return StripLayout(height: full + cardChrome, width: x, cards: cards)
    }

    public struct StripPlacement: Hashable, Sendable {
        public let card: Int
        public let x: CGFloat
    }

    public static func stripPlacements(_ layout: StripLayout, centre: Int?, viewWidth: CGFloat) -> [StripPlacement] {
        guard let first = layout.cards.first else { return [] }
        let held = layout.cards.first { card in centre.map { card.frames[$0] != nil } ?? false } ?? first
        let wanted = viewWidth / 2 - held.span.x - held.span.width / 2
        let offset = layout.slides(in: viewWidth) ? min(0, max(viewWidth - layout.width, wanted)) : (viewWidth - layout.width) / 2
        return layout.cards.indices.map { StripPlacement(card: $0, x: (layout.cards[$0].span.x + offset).rounded()) }
    }

    public static func captureSize(available: CGSize, backingScale: CGFloat, workspaces: Int, strip: Bool) -> CGSize {
        let height = (available.height * usableScreenFraction * StripGeometry.tallest).rounded(.up)
        var box = CGSize(width: height * screenRatio(for: available), height: height)
        let usable = usable(available)
        let cell = CardGrid.lattice(count: max(1, workspaces), in: usable, cellRatio: screenRatio(for: available), gap: cardGap,
                                    chrome: CGSize(width: 2 * cardPadding, height: cardChrome)).first?.size ?? usable
        if !strip { box = CGSize(width: min(box.width, inner(of: cell).width), height: min(box.height, inner(of: cell).height)) }
        return CGSize(width: (box.width * backingScale).rounded(.up), height: (box.height * backingScale).rounded(.up))
    }

    public static func stale(workspaces: [WorkspaceInfo], pictures: [Int: CGSize], sizes: [Int: CGSize]) -> [Int] {
        workspaces.flatMap(\.windows).filter { w in (sizes[w.windowId] ?? w.layoutRect?.size).map { !sameShape(pictures[w.windowId], $0) } ?? false }.map(\.windowId)
    }

    static func sameShape(_ picture: CGSize?, _ window: CGSize) -> Bool {
        guard let picture, picture.height > 0, window.height > 0 else { return false }
        return abs(picture.width / picture.height * window.height / window.width - 1) < 0.02
    }

    public static func stacking(windowId: Int, focused: Int, ghosts: Set<Int>) -> Double {
        ghosts.contains(windowId) ? 2 : windowId == focused ? 1 : 0
    }

    public static func tileOrigin(packed: CGSize, inner: CGSize) -> CGPoint {
        CGPoint(x: max(0, ((inner.width - packed.width) / 2).rounded(.down)),
                y: max(0, ((inner.height - packed.height) / 2).rounded(.down)))
    }

    public static func layoutSymbol(rootLayout: String) -> (name: String, help: String)? {
        switch rootLayout {
        case "h_tiles": return ("rectangle.split.2x1", "Tiles: windows side by side")
        case "v_tiles": return ("rectangle.split.1x2", "Tiles: windows one above another")
        case "h_accordion", "v_accordion": return ("rectangle.on.rectangle", "Accordion: windows stacked, one in front")
        default: return nil
        }
    }

}
