import Foundation

/// The windows inside a card, laid out as a justified photo grid: every tile at its own
/// width/height ratio, one shared picture height for the whole card, rows filled greedily
/// and then spread evenly so six windows are 3 + 3 rather than 4 + 2, a shorter row centred
/// under the wider one. Ported from
/// krn.overview's `CardGeometry.js`, where it was measured against flickr's per-row
/// justification (which wasted half a fixed box) and Knuth–Plass (which broke the height
/// search); see that repo's docs/LAYOUT.md for why this and not those.
public enum TilePacker {
    public struct Tile: Equatable, Sendable {
        public let x: CGFloat
        public let y: CGFloat
        public let width: CGFloat
        /// Picture plus caption.
        public let height: CGFloat
    }

    public struct Packed: Equatable, Sendable {
        /// Tile indices by row, in reading order.
        public let rows: [[Int]]
        public let height: CGFloat
        public let width: CGFloat
        public let tiles: [Tile]
    }

    /// Tiles at picture height `tileHeight` (each times its scale), in rows no wider than
    /// `width`. A tile wider than the card is clamped to it and loses height on its own,
    /// rather than capping the shared height for every tile beside it. A row is as tall as
    /// its tallest tile; shorter ones sit centred in it, each with `caption` under it.
    public static func packRows(ratios: [CGFloat], tileHeight: CGFloat, width: CGFloat,
                                gap: CGFloat, caption: CGFloat, scales: [CGFloat]?) -> Packed {
        let n = ratios.count
        var widths: [CGFloat] = [], heights: [CGFloat] = []
        for j in 0..<n {
            let scale = scales.map { $0[j] > 0 ? $0[j] : 1 } ?? 1
            var h = (tileHeight * scale).rounded(.down)
            var w = (ratios[j] * h).rounded(.down)
            if w > width { w = width; h = (width / max(0.01, ratios[j])).rounded(.down) }
            widths.append(max(1, w))
            heights.append(max(1, h))
        }

        // How many rows a greedy fill needs, then the same count filled evenly if that fits.
        var rowCount = 1
        var x: CGFloat = 0
        for j in 0..<n {
            if x > 0 && x + widths[j] > width { rowCount += 1; x = 0 }
            x += widths[j] + gap
        }
        let perRow = Int((Double(n) / Double(rowCount)).rounded(.up))
        var even = true
        for r in 0..<rowCount where even {
            let used = (r * perRow..<min(n, (r + 1) * perRow)).reduce(CGFloat(0)) { $0 + widths[$1] + gap }
            if used - gap > width { even = false }
        }

        var rows: [[Int]] = [[]]
        var rowHeights: [CGFloat] = [0]
        x = 0
        for j in 0..<n {
            let breaks = even ? (j > 0 && j % perRow == 0) : (x > 0 && x + widths[j] > width)
            if breaks { rows.append([]); rowHeights.append(0); x = 0 }
            rows[rows.count - 1].append(j)
            rowHeights[rows.count - 1] = max(rowHeights[rows.count - 1], heights[j])
            x += widths[j] + gap
        }

        // A row's width, so a shorter one can be centred under the widest rather than hung from the left.
        let rowWidths = rows.map { row in row.reduce(CGFloat(0)) { $0 + widths[$1] + gap } - gap }
        let widest = max(0, rowWidths.max() ?? 0)
        var tiles: [Tile] = Array(repeating: Tile(x: 0, y: 0, width: 0, height: 0), count: n)
        var y: CGFloat = 0
        for (r, row) in rows.enumerated() {
            x = ((widest - rowWidths[r]) / 2).rounded(.down)
            for j in row {
                tiles[j] = Tile(x: x, y: y + ((rowHeights[r] - heights[j]) / 2).rounded(.down),
                                width: widths[j], height: heights[j] + caption)
                x += widths[j] + gap
            }
            y += rowHeights[r] + caption + gap
        }
        return Packed(rows: n == 0 ? [] : rows, height: max(0, y - gap), width: widest, tiles: tiles)
    }

    /// The largest shared picture height whose rows fit in `width` × `height`: fitting is
    /// monotone in the height for a greedy fill, so a binary search finds it.
    public static func packHeight(ratios: [CGFloat], width: CGFloat, height: CGFloat,
                                  gap: CGFloat, caption: CGFloat, scales: [CGFloat]?) -> CGFloat {
        guard !ratios.isEmpty, width > 0, height > 0 else { return 0 }
        let maxScale = scales?.max() ?? 1
        var lo: CGFloat = 1
        var hi = max(1, ((height - caption) / max(1, maxScale)).rounded(.down))
        func fits(_ th: CGFloat) -> Bool {
            packRows(ratios: ratios, tileHeight: th, width: width, gap: gap, caption: caption, scales: scales).height <= height
        }
        while lo < hi {
            let mid = ((lo + hi) / 2).rounded(.up)
            if fits(mid) { lo = mid } else { hi = mid - 1 }
        }
        while lo > 1 && !fits(lo) { lo -= 1 }
        return lo
    }
}
