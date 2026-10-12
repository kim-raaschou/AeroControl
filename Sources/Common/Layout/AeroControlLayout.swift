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
    public static let minPictureHeight: CGFloat = 92

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

    public static func treeLayout(_ workspace: WorkspaceInfo, frames measured: [Int: CGRect], screen: CGRect?, inner: CGSize)
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
        func place(_ r: CGRect) -> CGRect {
            CGRect(x: box.minX + (r.minX - screen.minX) * scale, y: box.minY + (r.minY - screen.minY) * scale, width: r.width * scale, height: r.height * scale)
        }
        var frames: [Int: CGRect] = [:]
        for window in tiled { frames[window.windowId] = place(window.layoutRect!) }
        for window in windows where !window.isTiled {
            let size = measured[window.windowId].map { CGSize(width: min(box.width, $0.width * scale), height: min(box.height, $0.height * scale)) } ?? box.size
            let centred = CGRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
            frames[window.windowId] = window.isFloating ? measured[window.windowId].map { place($0).intersection(box) } ?? centred : centred
        }
        return (frames, Set(ghosts))
    }

    public struct LaidCard: Equatable, Sendable {
        public let workspace: String
        public let frame: CGRect
        public let frames: [Int: CGRect]
        public var ghosts: Set<Int> = []
        public var others: Set<Int> = []

        public var grid: GridWalk.Card {
            (frame, frames.filter { !others.contains($0.key) }.mapValues { $0.offsetBy(dx: frame.minX + cardPadding, dy: frame.minY + cardChrome - cardPadding) })
        }
    }

    public static func mapLayout(workspaces: [WorkspaceInfo], frames: [Int: CGRect], screens: [Int: CGRect], available: CGSize, filtering: Bool) -> [LaidCard] {
        let cells = CardGrid.lattice(count: workspaces.count, in: usable(available), cellRatio: screenRatio(for: available), gap: cardGap,
                                     chrome: CGSize(width: 2 * cardPadding, height: cardChrome))
        return zip(workspaces, cells).map { ws, cell in
            let screen = screens[ws.screenIndex], inner = inner(of: cell.size)
            let laid = filtering ? nil : treeLayout(ws, frames: frames, screen: screen, inner: inner)
            let placed = laid ?? packed(ws.windows, frames: frames, screen: screen, inner: inner, caption: filtering ? captionLane : 0)
            let standIn = [ws.standIn: CGRect(origin: .zero, size: inner)].filter { _ in placed.frames.isEmpty }
            return LaidCard(workspace: ws.name, frame: cell, frames: placed.frames.merging(standIn) { a, _ in a }, ghosts: placed.ghosts)
        }
    }

    static func packed(_ windows: [WindowInfo], frames measured: [Int: CGRect], screen: CGRect?, inner: CGSize, caption: CGFloat, oneRow: Bool = false) -> (frames: [Int: CGRect], ghosts: Set<Int>) {
        let ratios = ratios(of: windows, sizes: measured.mapValues(\.size), fallback: screenRatio(for: screen?.size ?? inner))
        let gap = packedGap(screen: screen?.size, inner: inner)
        let height = oneRow ? min(inner.height, ((inner.width - gap) / max(0.01, ratios.reduce(0, +))).rounded(.down))
            : TilePacker.packHeight(ratios: ratios, width: inner.width, height: inner.height, gap: gap, caption: caption)
        let packed = TilePacker.packRows(ratios: ratios, tileHeight: max(1, height), width: inner.width, gap: gap, caption: caption)
        let origin = tileOrigin(packed: CGSize(width: packed.width, height: packed.height), inner: inner)
        let frames = Dictionary(zip(windows.map(\.windowId), packed.tiles.map { CGRect(x: origin.x + $0.x, y: origin.y + $0.y, width: $0.width, height: $0.height) }),
                                uniquingKeysWith: { _, b in b })
        return (frames, [])
    }

    public static let tallest: CGFloat = 0.45
    public static let seen: CGFloat = 3.5

    public static func stripCardHeight(view: CGFloat, cards: Int, aspect: CGFloat, chrome: CGFloat, panelHeight: CGFloat) -> CGFloat {
        let each = view / min(CGFloat(max(1, cards)), seen) - chrome
        return min((panelHeight * tallest).rounded(), (each / max(0.01, aspect)).rounded(.down))
    }

    public static func stripLayout(groups: [WorkspaceInfo], bundleId: String, frames: [Int: CGRect], screens: [Int: CGRect], available: CGSize) -> [LaidCard] {
        let areas = groups.map { screens[$0.screenIndex] ?? CGRect(origin: .zero, size: available) }
        let aspects = areas.map { $0.width / max(1, $0.height) }, view = usable(available)
        let full = stripCardHeight(view: view.width, cards: groups.count, aspect: aspects.reduce(0, +) / CGFloat(max(1, groups.count)),
                                   chrome: 2 * cardPadding + cardGap, panelHeight: view.height)
        let room = (view.width / min(CGFloat(max(1, groups.count)), seen) - 2 * cardPadding - cardGap).rounded(.down)
        var x: CGFloat = 0
        return groups.indices.map { g in
            var inner = CGSize(width: (full * aspects[g]).rounded(), height: full), laid: (frames: [Int: CGRect], ghosts: Set<Int>)
            let stacked = groups[g].rootLayout == "v_tiles" && groups[g].windows.count == 2 && groups[g].windows.allSatisfy(\.isTiled)
            if !stacked, let tree = treeLayout(groups[g], frames: frames, screen: areas[g], inner: inner) {
                laid = tree
            } else {
                let packed = packed(groups[g].windows, frames: frames, screen: areas[g], inner: CGSize(width: max(inner.width, room), height: full),
                                    caption: 0, oneRow: groups[g].windows.count == 2)
                let used = packed.frames.values.reduce(CGRect.null) { $0.union($1) }
                inner.width = used.width.rounded(.up)
                laid = (packed.frames.mapValues { $0.offsetBy(dx: -used.minX, dy: 0) }, packed.ghosts)
            }
            let card = LaidCard(workspace: groups[g].name, frame: CGRect(x: x, y: 0, width: inner.width + 2 * cardPadding, height: full + cardChrome), frames: laid.frames,
                                ghosts: laid.ghosts, others: Set(groups[g].windows.filter { $0.bundleId != bundleId }.map(\.windowId)))
            x = card.frame.maxX + cardGap
            return card
        }
    }

    public static func stripOffset(_ cards: [LaidCard], held: Int, viewWidth: CGFloat) -> CGFloat {
        let width = cards.last?.frame.maxX ?? 0, centre = cards.indices.contains(held) ? cards[held].frame.midX : 0
        return (width > viewWidth ? min(0, max(viewWidth - width, viewWidth / 2 - centre)) : (viewWidth - width) / 2).rounded()
    }

    public static func stale(workspaces: [WorkspaceInfo], pictures: [Int: CGSize], sizes: [Int: CGSize]) -> [Int] {
        workspaces.flatMap(\.windows).filter { w in (sizes[w.windowId] ?? w.layoutRect?.size).map { !sameShape(pictures[w.windowId], $0) } ?? false }.map(\.windowId)
    }

    public static func sameShape(_ picture: CGSize?, _ window: CGSize) -> Bool {
        guard let picture, picture.height > 0, window.height > 0 else { return false }
        return abs(picture.width / picture.height * window.height / window.width - 1) < 0.02
    }

    public static func tileOrigin(packed: CGSize, inner: CGSize) -> CGPoint {
        CGPoint(x: max(0, ((inner.width - packed.width) / 2).rounded(.down)),
                y: max(0, ((inner.height - packed.height) / 2).rounded(.down)))
    }

    public static func layoutSymbol(rootLayout: String) -> (name: String, help: String)? {
        switch rootLayout {
        case "h_tiles": return ("rectangle.split.2x1", "Tiles: windows side by side — click to stack them")
        case "v_tiles": return ("rectangle.split.1x2", "Tiles: windows one above another — click to stack them")
        case "h_accordion", "v_accordion": return ("rectangle.on.rectangle", "Accordion: windows stacked, one in front — click to tile them")
        default: return nil
        }
    }

}

public enum AeroControlMetrics {
    public static func badgeSize(width: CGFloat) -> CGFloat { min(36, max(22, width * 0.11)) }

    public static func fit(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = min(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    public static func cover(_ imageSize: CGSize, into box: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return box }
        let scale = max(box.width / imageSize.width, box.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    public static func pixelSnapped(_ size: CGSize, scale: CGFloat) -> CGSize {
        CGSize(width: max(1, (size.width * scale).rounded()) / scale, height: max(1, (size.height * scale).rounded()) / scale)
    }

    public static func focusRingWidth(scale: CGFloat) -> CGFloat { 1 + scale }
    public static let snapshotRadius: CGFloat = 6
}
