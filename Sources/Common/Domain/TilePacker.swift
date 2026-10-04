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
        public let height: CGFloat
        public let width: CGFloat
        public let tiles: [Tile]
    }

    /// Tiles at picture height `tileHeight`, in rows no wider than `width`. A tile wider than
    /// the card is clamped to it and loses height on its own, in a row of its own, rather than
    /// capping the shared height for every tile beside it. Each tile has `caption` under it.
    public static func packRows(ratios: [CGFloat], tileHeight: CGFloat, width: CGFloat,
                                gap: CGFloat, caption: CGFloat) -> Packed {
        guard !ratios.isEmpty else { return Packed(height: 0, width: 0, tiles: []) }
        let sizes = ratios.map { ratio in
            let h = tileHeight.rounded(.down), w = (ratio * h).rounded(.down)
            let clamped = w > width ? CGSize(width: width, height: (width / max(0.01, ratio)).rounded(.down)) : CGSize(width: w, height: h)
            return CGSize(width: max(1, clamped.width), height: max(1, clamped.height))
        }
        func rowWidth(_ row: [Int]) -> CGFloat { row.reduce(-gap) { $0 + sizes[$1].width + gap } }

        // Rows filled greedily, then the same number filled evenly if that fits.
        var greedy: [[Int]] = [[]]
        for j in sizes.indices {
            if !greedy[greedy.count - 1].isEmpty, rowWidth(greedy[greedy.count - 1] + [j]) > width { greedy.append([]) }
            greedy[greedy.count - 1].append(j)
        }
        let perRow = Int((Double(sizes.count) / Double(greedy.count)).rounded(.up))
        let even = stride(from: 0, to: sizes.count, by: perRow).map { Array($0..<min(sizes.count, $0 + perRow)) }
        let rows = even.allSatisfy { rowWidth($0) <= width } ? even : greedy

        // A shorter row is centred under the widest rather than hung from the left.
        let widest = rows.map(rowWidth).max() ?? 0
        var tiles = [Tile](repeating: Tile(x: 0, y: 0, width: 0, height: 0), count: sizes.count)
        var y: CGFloat = 0
        for row in rows {
            var x = ((widest - rowWidth(row)) / 2).rounded(.down)
            for j in row {
                tiles[j] = Tile(x: x, y: y, width: sizes[j].width, height: sizes[j].height + caption)
                x += sizes[j].width + gap
            }
            y += (row.map { sizes[$0].height }.max() ?? 0) + caption + gap
        }
        return Packed(height: y - gap, width: widest, tiles: tiles)
    }

    /// The largest shared picture height whose rows fit in `width` × `height`: fitting is
    /// monotone in the height for a greedy fill, so a binary search finds it.
    public static func packHeight(ratios: [CGFloat], width: CGFloat, height: CGFloat,
                                  gap: CGFloat, caption: CGFloat) -> CGFloat {
        guard !ratios.isEmpty, width > 0, height > 0 else { return 0 }
        var lo: CGFloat = 1
        var hi = max(1, (height - caption).rounded(.down))
        func fits(_ th: CGFloat) -> Bool {
            packRows(ratios: ratios, tileHeight: th, width: width, gap: gap, caption: caption).height <= height
        }
        while lo < hi {
            let mid = ((lo + hi) / 2).rounded(.up)
            if fits(mid) { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
