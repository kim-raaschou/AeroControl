import CoreGraphics
import Foundation

/// The tiling tree of a workspace, rebuilt from what a release AeroSpace lets us read about a
/// hidden one: the windows' sizes (AeroSpace parks a hidden window by position only, so its
/// size is the one it had on screen) and the root's axis (`workspace-root-container-layout`).
/// In a tiles container every child spans the container across its axis and the children's
/// sizes along it add up to the container's, so the sizes decide the shape. Where they do not
/// force it there is no tree, and the card draws tiles. Never a guessed tree. The fallback for
/// an AeroSpace without `%{window-layout-rect}`; with it the card draws AeroSpace's own rects.
public enum WorkspaceTree {
    public enum Axis: Equatable, Sendable {
        case horizontal, vertical
        var flipped: Axis { self == .horizontal ? .vertical : .horizontal }

        /// From AeroSpace's `workspace-root-container-layout`: tiles have an axis, an
        /// accordion has none (its windows overlap, there is nothing to reconstruct).
        public init?(rootLayout: String) {
            switch rootLayout {
            case "h_tiles": self = .horizontal
            case "v_tiles": self = .vertical
            default: return nil
            }
        }
    }

    public indirect enum Node: Equatable, Sendable {
        case window(Int)
        case split(Axis, [Node])
    }

    public struct Window: Equatable, Sendable {
        public let id: Int
        public let size: CGSize
        public init(id: Int, size: CGSize) { self.id = id; self.size = size }
    }

    /// The tree, or nil when the sizes do not force one. `area` is the screen the workspace
    /// lives on (its visible frame); `maxGap` is the largest gap AeroSpace could have been
    /// told to leave, so a window `2 × maxGap` short of the area still counts as spanning it.
    /// The windows come in AeroSpace's listing order, which says nothing about their places,
    /// so only a forced reading is made: see `parseUnordered`.
    public static func reconstruct(windows: [Window], root: Axis, area: CGSize, maxGap: CGFloat = 40) -> Node? {
        guard windows.count > 1 else { return windows.first.map { .window($0.id) } }
        return parseUnordered(windows, axis: root, extent: area, maxGap: maxGap)
    }

    /// Only a forced reading is safe: windows that span the area are children; the rest fall
    /// into columns by width, one column per width, each filled by windows that span it, all in
    /// the order first listed. Two columns of one width, a column holding a row, a grid: the
    /// sizes do not force those, and they are left to tiles.
    private static func parseUnordered(_ ws: [Window], axis: Axis, extent: CGSize, maxGap: CGFloat) -> Node? {
        var groups: [[Window]] = []
        for win in ws {
            if !spans(win, axis: axis, extent: extent, maxGap: maxGap),
               let i = groups.firstIndex(where: { !spans($0[0], axis: axis, extent: extent, maxGap: maxGap) && abs($0[0].size.along(axis) - win.size.along(axis)) <= 2 }) {
                groups[i].append(win)
            } else {
                groups.append([win])
            }
        }
        var nodes: [Node] = [], along: CGFloat = 0
        for group in groups {
            let width = group[0].size.along(axis)
            along += width
            if spans(group[0], axis: axis, extent: extent, maxGap: maxGap) { nodes.append(.window(group[0].id)); continue }
            let slab = CGSize(along: width, across: extent.across(axis), axis: axis)
            guard group.count >= 2, group.allSatisfy({ spans($0, axis: axis.flipped, extent: slab, maxGap: maxGap) }),
                  fits(group.reduce(0) { $0 + $1.size.along(axis.flipped) }, count: group.count, in: slab.along(axis.flipped), maxGap: maxGap)
            else { return nil }
            nodes.append(.split(axis.flipped, group.map { .window($0.id) }))
        }
        guard nodes.count >= 2, fits(along, count: nodes.count, in: extent.along(axis), maxGap: maxGap) else { return nil }
        return .split(axis, nodes)
    }

    /// A window spans its container across the axis: within the gaps of it, never wider.
    private static func spans(_ win: Window, axis: Axis, extent: CGSize, maxGap: CGFloat) -> Bool {
        let across = win.size.across(axis)
        return across >= extent.across(axis) - 2 * maxGap && across <= extent.across(axis) + maxGap
    }

    /// Children's sizes plus the gaps between and around them make the container: the gaps are
    /// unknown but bounded.
    private static func fits(_ sum: CGFloat, count: Int, in extent: CGFloat, maxGap: CGFloat) -> Bool {
        sum <= extent + 1 && sum >= extent - CGFloat(count + 1) * maxGap
    }

    /// Where each window goes when the tree is drawn into `box`, a box of the screen's shape:
    /// every window at its own size, at the scale that maps the screen onto the box, the tiled
    /// area centred, so the screen's outer gaps show as the margin around it and no picture is
    /// stretched or banded. `gap` is the gap AeroSpace keeps between windows, read once for
    /// the whole overview (`innerGap`); nil reads it off this tree, and where that is not
    /// possible either the windows sit edge to edge.
    public static func frames(of node: Node, windows: [Window], screen: CGSize, in box: CGRect, gap: CGFloat?) -> [Int: CGRect] {
        let sizes = Dictionary(windows.map { ($0.id, $0.size) }, uniquingKeysWith: { a, _ in a })
        let gap = gap ?? inferredGap(node, sizes: sizes) ?? 0
        let area = natural(node, sizes: sizes, gap: gap)
        let scale = min(box.width / max(1, screen.width), box.height / max(1, screen.height))
        let origin = CGPoint(x: box.midX - area.width * scale / 2, y: box.midY - area.height * scale / 2)
        var out: [Int: CGRect] = [:]
        place(node, at: origin, scale: scale, gap: gap, sizes: sizes, into: &out)
        return out
    }

    /// The gap AeroSpace keeps between windows, as this tree shows it: a nested container runs
    /// its parent's full width, its children's sizes add up to less, and the difference is
    /// shared by the gaps between them. Nil when nothing is nested to read it from. It is a
    /// setting, the same on every workspace, so one tree that shows it serves them all.
    public static func innerGap(of node: Node, windows: [Window]) -> CGFloat? {
        inferredGap(node, sizes: Dictionary(windows.map { ($0.id, $0.size) }, uniquingKeysWith: { a, _ in a }))
    }

    /// A node's size as AeroSpace has it, gaps included: a window's own; a container's the sum
    /// of its children's along its axis, the widest of them across.
    private static func natural(_ node: Node, sizes: [Int: CGSize], gap: CGFloat) -> CGSize {
        switch node {
        case .window(let id): return sizes[id] ?? CGSize(width: 1, height: 1)
        case .split(let axis, let children):
            let parts = children.map { natural($0, sizes: sizes, gap: gap) }
            return CGSize(along: parts.reduce(0) { $0 + $1.along(axis) } + gap * CGFloat(children.count - 1),
                          across: parts.map { $0.across(axis) }.max() ?? 1, axis: axis)
        }
    }

    private static func inferredGap(_ node: Node, sizes: [Int: CGSize]) -> CGFloat? {
        guard case .split(let axis, let children) = node else { return nil }
        let across = children.compactMap { child -> CGFloat? in
            if case .window(let id) = child { return sizes[id]?.across(axis) } else { return nil }
        }.max()
        for child in children {
            guard case .split(let own, let members) = child, members.count >= 2 else { continue }
            if let across {
                let filled = members.reduce(0) { $0 + natural($1, sizes: sizes, gap: 0).along(own) }
                let gap = (across - filled) / CGFloat(members.count - 1)
                if gap >= 0 { return gap }
            }
            if let deeper = inferredGap(child, sizes: sizes) { return deeper }
        }
        return nil
    }

    private static func place(_ node: Node, at origin: CGPoint, scale: CGFloat, gap: CGFloat, sizes: [Int: CGSize], into out: inout [Int: CGRect]) {
        switch node {
        case .window(let id):
            let size = natural(node, sizes: sizes, gap: gap)
            out[id] = CGRect(origin: origin, size: CGSize(width: size.width * scale, height: size.height * scale))
        case .split(let axis, let children):
            var offset: CGFloat = 0
            for child in children {
                let at = axis == .horizontal ? CGPoint(x: origin.x + offset, y: origin.y) : CGPoint(x: origin.x, y: origin.y + offset)
                place(child, at: at, scale: scale, gap: gap, sizes: sizes, into: &out)
                offset += (natural(child, sizes: sizes, gap: gap).along(axis) + gap) * scale
            }
        }
    }
}

private extension CGSize {
    func along(_ axis: WorkspaceTree.Axis) -> CGFloat { axis == .horizontal ? width : height }
    func across(_ axis: WorkspaceTree.Axis) -> CGFloat { axis == .horizontal ? height : width }
    init(along: CGFloat, across: CGFloat, axis: WorkspaceTree.Axis) {
        self = axis == .horizontal ? CGSize(width: along, height: across) : CGSize(width: across, height: along)
    }
}
