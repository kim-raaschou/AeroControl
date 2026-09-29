import CoreGraphics
import Foundation

/// The workspace cards on the screen: ordered, weighted cells in rows. Widths inside a row
/// follow weight — an empty workspace is a strip, a crowded one takes a double share —
/// and rows are as tall as what they show, the whole grid centred. For up to ten cards
/// every way of breaking them into rows is tried and the one whose smallest window comes
/// out largest wins, if it beats the default shape by `rowGain`, never stands a card
/// upright, and never leaves a row of empty workspaces between two busy ones. Ported from
/// krn.overview's `weightedCells`; the card's need is estimated with uniform tiles of
/// `tileRatio`, so a card's place depends on how many windows it holds, not their shapes.
public enum CardGrid {
    public struct Slot: Equatable, Sendable {
        /// 0 for an empty workspace (a strip), 1 for an ordinary one, 2 for a crowded one.
        public let weight: CGFloat
        public let count: Int
        public init(weight: CGFloat, count: Int) { self.weight = weight; self.count = count }
    }

    public struct Options: Sendable {
        public var gap: CGFloat
        /// Width / height of the proxy tile a card's need is estimated with: the screen's.
        public var tileRatio: CGFloat
        public var cardPadding: CGFloat
        /// A card's height that is not tiles: padding and the badge lane.
        public var chrome: CGFloat
        /// Width of an empty card.
        public var narrow: CGFloat
        public var tileGap: CGFloat
        public var caption: CGFloat
        /// A break of its own must beat the default shape's smallest window by this factor.
        public var rowGain: CGFloat = 1.05
        /// Width / height the default shape aims its cells at.
        public var cardShape: CGFloat = 1.4

        public init(gap: CGFloat, tileRatio: CGFloat, cardPadding: CGFloat, chrome: CGFloat,
                    narrow: CGFloat, tileGap: CGFloat, caption: CGFloat) {
            self.gap = gap; self.tileRatio = tileRatio; self.cardPadding = cardPadding; self.chrome = chrome
            self.narrow = narrow; self.tileGap = tileGap; self.caption = caption
        }
    }

    public struct Cell: Equatable, Sendable {
        public let index: Int
        public let frame: CGRect
    }

    public struct Layout: Equatable, Sendable {
        public let cells: [Cell]
        /// Slot indices by row.
        public let rows: [[Int]]
        /// The picture height of the smallest window on the screen, by the proxy estimate.
        public let smallest: CGFloat
        /// Whether any busy card came out taller than wide.
        let upright: Bool
    }

    public static func layout(_ slots: [Slot], in box: CGSize, options o: Options) -> Layout {
        let n = slots.count
        guard n > 0, box.width > 0, box.height > 0 else {
            return Layout(cells: slots.indices.map { Cell(index: $0, frame: .zero) }, rows: n == 0 ? [] : [Array(0..<n)],
                          smallest: 0, upright: false)
        }
        // The default shape: the column count whose cells are nearest `cardShape` with the
        // fewest empty cells.
        var columns = 3
        var bestScore = CGFloat.infinity
        for c in 1...n {
            let r = (n + c - 1) / c
            let cw = (box.width - o.gap * CGFloat(c - 1)) / CGFloat(c)
            let ch = (box.height - o.gap * CGFloat(r - 1)) / CGFloat(r)
            guard cw > 0, ch > 0 else { continue }
            let score = CGFloat(c * r - n) * 0.5 + abs(log((cw / ch) / o.cardShape))
            if score < bestScore - 1e-9 { bestScore = score; columns = c }
        }
        let byDefault = stride(from: 0, to: n, by: columns).map { Array($0..<min(n, $0 + columns)) }
        var chosen = layoutRows(byDefault, slots, box, o)
        if n <= 10 {
            var found: Layout?
            for mask in 0..<(1 << (n - 1)) {
                var rows: [[Int]] = [[0]]
                for i in 1..<n {
                    if (mask >> (i - 1)) & 1 == 1 { rows.append([i]) } else { rows[rows.count - 1].append(i) }
                }
                if emptyRowBetween(rows, slots) { continue }
                let tried = layoutRows(rows, slots, box, o)
                if tried.upright { continue }
                if found == nil || tried.smallest > found!.smallest + 0.5 { found = tried }
            }
            if let found, emptyRowBetween(byDefault, slots) || found.smallest >= chosen.smallest * o.rowGain { chosen = found }
        }
        return chosen
    }

    /// A row with no windows standing between two rows that have some.
    private static func emptyRowBetween(_ rows: [[Int]], _ slots: [Slot]) -> Bool {
        let busy = rows.map { $0.contains { slots[$0].count > 0 } }
        return busy.indices.contains { i in !busy[i] && busy[..<i].contains(true) && busy[(i + 1)...].contains(true) }
    }

    private static func layoutRows(_ rows: [[Int]], _ slots: [Slot], _ box: CGSize, _ o: Options) -> Layout {
        let n = slots.count
        // Widths: weight shares of what the empties leave, or equal when even that is too little.
        var widthOf = [CGFloat](repeating: 0, count: n)
        for row in rows {
            let m = CGFloat(row.count)
            var avail = box.width - o.gap * (m - 1)
            var weights: CGFloat = 0
            for i in row { if slots[i].weight > 0 { weights += slots[i].weight } else { avail -= o.narrow } }
            if avail < 0 {
                for i in row { widthOf[i] = (box.width - o.gap * (m - 1)) / m }
                continue
            }
            for i in row { widthOf[i] = slots[i].weight > 0 && weights > 0 ? avail * slots[i].weight / weights : o.narrow }
        }

        let shortH = (o.chrome + o.narrow / o.tileRatio).rounded()
        // What a card needs at picture height `s`, with uniform proxy tiles.
        func heightFor(_ slot: Slot, _ width: CGFloat, _ s: CGFloat) -> CGFloat {
            guard slot.count > 0 else { return shortH }
            let tileWidth = s * o.tileRatio
            let perRow = max(1, Int(((width - o.cardPadding * 2 + o.tileGap) / (tileWidth + o.tileGap)).rounded(.down)))
            let need = CGFloat((slot.count + perRow - 1) / perRow)
            return need * (s + o.caption) + (need - 1) * o.tileGap + o.chrome
        }
        let heavy = rows.map { $0.contains { slots[$0].weight > 0 } }
        let freeH = box.height - o.gap * CGFloat(rows.count - 1)
        func rowHeights(at s: CGFloat) -> (heights: [CGFloat], total: CGFloat) {
            var out: [CGFloat] = []
            for (r, row) in rows.enumerated() {
                guard heavy[r] else { out.append(min(shortH, freeH / CGFloat(rows.count))); continue }
                out.append(row.reduce(shortH) { max($0, heightFor(slots[$1], widthOf[$1], s)) })
            }
            return (out, out.reduce(0, +))
        }
        // The largest picture height whose rows still fit the box.
        var lo: CGFloat = 1, hi = max(2, freeH)
        var iterations = 0
        while iterations < 24 && hi - lo > 0.5 {
            let mid = (lo + hi) / 2
            if rowHeights(at: mid).total <= freeH { lo = mid } else { hi = mid }
            iterations += 1
        }
        let solved = rowHeights(at: lo)

        var cells = [Cell](repeating: Cell(index: 0, frame: .zero), count: n)
        var y = max(0, (freeH - solved.total) / 2)
        for (r, row) in rows.enumerated() {
            let rowWidth = row.reduce(o.gap * CGFloat(row.count - 1)) { $0 + widthOf[$1] }
            var x = max(0, (box.width - rowWidth) / 2)
            for i in row {
                cells[i] = Cell(index: i, frame: CGRect(x: x.rounded(), y: y.rounded(),
                                                        width: widthOf[i].rounded(.down), height: solved.heights[r].rounded(.down)))
                x += widthOf[i] + o.gap
            }
            y += solved.heights[r] + o.gap
        }
        var smallest = CGFloat.infinity
        var upright = false
        for i in 0..<n where slots[i].count > 0 {
            if cells[i].frame.height > cells[i].frame.width { upright = true }
            smallest = min(smallest, fitHeight(slots[i].count, cells[i].frame.width - o.cardPadding * 2, cells[i].frame.height - o.chrome, o))
        }
        return Layout(cells: cells, rows: rows, smallest: smallest == .infinity ? 0 : smallest, upright: upright)
    }

    /// The largest uniform picture height `count` proxy tiles get in `w` × `h`, over every row count.
    private static func fitHeight(_ count: Int, _ w: CGFloat, _ h: CGFloat, _ o: Options) -> CGFloat {
        var best: CGFloat = 0
        for k in 1...count {
            let perRow = CGFloat((count + k - 1) / k)
            let byW = (w - (perRow - 1) * o.tileGap) / perRow / o.tileRatio
            let byH = (h - CGFloat(k - 1) * o.tileGap) / CGFloat(k) - o.caption
            best = max(best, min(byW, byH))
        }
        return best
    }
}
