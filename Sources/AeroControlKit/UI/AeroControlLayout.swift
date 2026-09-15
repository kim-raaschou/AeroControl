import CoreGraphics

/// Pure layout math for the full-screen overview, Mission-Control style: space follows
/// content. Cards are laid out in rows; within a row each card's width is proportional
/// to its weight (≈ √windows, empty workspaces get a badge-sized sliver), rows are
/// balanced by weight, and a card's windows fill it as a grid of 3:2 tiles (or square
/// icons) using whichever column count yields the largest tiles. All unit-tested.
public enum AeroControlLayout {
    public static let usableScreenFraction: CGFloat = 0.94
    public static let cardGap: CGFloat = 24
    /// Tile height as a fraction of its width.
    public static let tileAspect: CGFloat = 2.0 / 3.0
    public static let tileSpacing: CGFloat = 14
    public static let cardPadding: CGFloat = 18
    /// Vertical room reserved at the top of a card for the workspace badge.
    public static let badgeLane: CGFloat = 44
    public static let minTileWidth: CGFloat = 36
    /// Largest square icon tile; icons bigger than this stop looking like icons.
    public static let maxIconTile: CGFloat = 128
    /// Narrowest card that still shows windows; below this only the badge is drawn.
    public static let minCardWidth: CGFloat = 150
    /// Diameter of the workspace badge in the card header.
    public static let badgeSize: CGFloat = 24
    /// An empty card is exactly the badge plus the card padding on both sides, so the badge
    /// sits in the same corner as on full cards and is centered in the narrow card as well.
    public static let emptyCardWidth: CGFloat = badgeSize + 2 * cardPadding
    public static let emptyWeight: CGFloat = 0.35

    /// How much width a workspace deserves relative to the others.
    public static func weight(windowCount: Int) -> CGFloat {
        windowCount <= 0 ? emptyWeight : CGFloat(Double(windowCount).squareRoot())
    }

    /// Number of rows for `count` cards: 1–3 → 1, 4–6 → 2, 7–12 → 3, then 4 per row.
    public static func rowCount(forCount count: Int) -> Int {
        switch count {
        case ...0: 0
        case 1...3: 1
        case 4...6: 2
        case 7...12: 3
        default: Int((Double(count) / 4).rounded(.up))
        }
    }

    /// Smallest row height; keeps a row of empty workspaces readable.
    public static let minRowHeight: CGFloat = 120

    /// Splits `weights` into `rowCount` contiguous, non-empty groups (order preserved),
    /// closing a row when the next card would move its weight further from the ideal
    /// share than leaving it out, while always keeping one card for every later row.
    public static func partition(weights: [CGFloat], rowCount: Int) -> [Range<Int>] {
        guard rowCount > 0, !weights.isEmpty else { return [] }
        let rows = min(rowCount, weights.count)
        let target = weights.reduce(0, +) / CGFloat(rows)
        var result: [Range<Int>] = []
        var start = 0, sum: CGFloat = 0
        for (i, w) in weights.enumerated() {
            let rowsLeft = rows - result.count
            let itemsLeft = weights.count - i
            let mustClose = itemsLeft == rowsLeft - 1
            let worse = i > start && rowsLeft > 1 && abs(sum + w - target) > abs(sum - target)
            if mustClose || worse {
                result.append(start..<i); start = i; sum = 0
            }
            sum += w
        }
        result.append(start..<weights.count)
        return result
    }

    /// Card sizes per row for `windowCounts` (in AeroSpace order) inside `available`.
    /// Empty workspaces get `emptyCardWidth`; the rest share the remaining width by weight,
    /// never below `minCardWidth` when the row allows it.
    /// Snapshot cells are shaped like the screen the windows live on.
    public static func previewAspect(for available: CGSize) -> CGFloat {
        available.width > 0 ? available.height / available.width : tileAspect
    }

    public static func cardSizes(windowCounts: [Int], available: CGSize) -> [[CGSize]] {
        let n = windowCounts.count
        guard n > 0, available.width > 0, available.height > 0 else { return [] }
        let aspect = previewAspect(for: available)
        let weights = windowCounts.map(weight(windowCount:))
        let rows = partition(weights: weights, rowCount: rowCount(forCount: n))
        let counts = rows.map { Array(windowCounts[$0]) }
        let widths = counts.map { rowWidths(windowCounts: $0, rowWidth: available.width) }
        let start = rowHeights(rowWeights: rows.map { weights[$0].reduce(0, +) }, totalHeight: available.height)
        let heights = rowHeights(windowCounts: counts, widths: widths, start: start, aspect: aspect)
        return zip(zip(counts, widths), heights).map { row, height in
            row.1.map { CGSize(width: $0, height: height) }
        }
    }

    /// Snapshot area a row of cards yields at `height`: what the height search maximizes.
    static func snapshotArea(windowCounts: [Int], widths: [CGFloat], height: CGFloat, aspect: CGFloat) -> CGFloat {
        zip(windowCounts, widths).reduce(0) { sum, card in
            guard card.0 > 0 else { return sum }
            let tile = tileGrid(windowCount: card.0, card: CGSize(width: card.1, height: height), aspect: aspect).width
            return sum + CGFloat(card.0) * tile * tile * aspect
        }
    }

    /// Row heights that maximize the total snapshot area, starting from `start` (the weight
    /// share) and moving height between rows in steps of 2% while that grows the area. A
    /// row whose tiles are limited by width gives height away for free; a row with a 2x2
    /// grid limited by height takes it.
    static func rowHeights(windowCounts: [[Int]], widths: [[CGFloat]], start: [CGFloat], aspect: CGFloat) -> [CGFloat] {
        var heights = start
        let step = (start.reduce(0, +) / 50).rounded(.down)
        func area(_ h: [CGFloat]) -> CGFloat {
            h.indices.reduce(0) { $0 + snapshotArea(windowCounts: windowCounts[$1], widths: widths[$1], height: h[$1], aspect: aspect) }
        }
        var best = area(heights), improved = step > 0
        while improved {
            improved = false
            for from in heights.indices where heights[from] - step >= minRowHeight {
                for to in heights.indices where to != from {
                    var trial = heights
                    trial[from] -= step; trial[to] += step
                    let score = area(trial)
                    if score > best { best = score; heights = trial; improved = true }
                }
            }
        }
        return heights
    }

    /// Rows share the height by their weight sums, each at least `minRowHeight`.
    static func rowHeights(rowWeights: [CGFloat], totalHeight: CGFloat) -> [CGFloat] {
        let usable = totalHeight - CGFloat(rowWeights.count - 1) * cardGap
        let total = rowWeights.reduce(0, +)
        var heights = rowWeights.map { max(minRowHeight, (usable * $0 / total)) }
        let overflow = heights.reduce(0, +) - usable
        if overflow > 0 {   // clamping pushed us over: take it back from the rows above the minimum
            let flexible = heights.indices.filter { heights[$0] > minRowHeight }
            let flexTotal = flexible.map { heights[$0] - minRowHeight }.reduce(0, +)
            for i in flexible where flexTotal > 0 { heights[i] -= overflow * (heights[i] - minRowHeight) / flexTotal }
        }
        return heights.map { $0.rounded(.down) }
    }

    static func rowWidths(windowCounts: [Int], rowWidth: CGFloat) -> [CGFloat] {
        let usable = rowWidth - CGFloat(windowCounts.count - 1) * cardGap
        var widths = windowCounts.map { $0 <= 0 ? emptyCardWidth : CGFloat(0) }
        let flexible = windowCounts.indices.filter { windowCounts[$0] > 0 }
        guard !flexible.isEmpty else {
            return widths.map { _ in (usable / CGFloat(windowCounts.count)).rounded(.down) }
        }
        var remaining = usable - widths.reduce(0, +)
        var pool = flexible
        // Give every flexible card at least minCardWidth first, then share the rest by weight.
        while !pool.isEmpty {
            let totalWeight = pool.map { weight(windowCount: windowCounts[$0]) }.reduce(0, +)
            let tooSmall = pool.filter { remaining * weight(windowCount: windowCounts[$0]) / totalWeight < minCardWidth }
            if tooSmall.isEmpty || tooSmall.count == pool.count { break }
            for i in tooSmall { widths[i] = minCardWidth; remaining -= minCardWidth }
            pool.removeAll { tooSmall.contains($0) }
        }
        let totalWeight = pool.map { weight(windowCount: windowCounts[$0]) }.reduce(0, +)
        for i in pool { widths[i] = (remaining * weight(windowCount: windowCounts[i]) / totalWeight).rounded(.down) }
        return widths
    }

    /// A grid whose tiles are within this fraction of the largest possible is "as good":
    /// among those the one with more rows wins, so four windows in a wide card become
    /// 2x2 rather than a strip of four with empty space below (Mission Control style).
    public static let gridTolerance: CGFloat = 0.20

    /// Column count and tile width for `windowCount` tiles inside the card's inner area:
    /// the largest tiles, with a preference for squarer grids within `gridTolerance`.
    /// `aspect` is height/width: `tileAspect` or 1 (icons).
    public static func tileGrid(windowCount: Int, card: CGSize, aspect: CGFloat = tileAspect) -> (columns: Int, width: CGFloat) {
        guard windowCount > 0 else { return (0, 0) }
        let innerWidth = card.width - 2 * cardPadding
        let innerHeight = card.height - cardPadding - badgeLane
        let candidates: [(columns: Int, width: CGFloat)] = (1...windowCount).map { columns in
            let rows = Int((Double(windowCount) / Double(columns)).rounded(.up))
            let byWidth = (innerWidth - CGFloat(columns - 1) * tileSpacing) / CGFloat(columns)
            let byHeight = ((innerHeight - CGFloat(rows - 1) * tileSpacing) / CGFloat(rows)) / aspect
            return (columns, min(byWidth, byHeight))
        }
        let largest = candidates.map(\.width).max() ?? 0
        // Candidates are in ascending column order, so the first good enough has the most rows.
        let best = candidates.first { $0.width >= largest * (1 - gridTolerance) } ?? (1, 0)
        var width = best.width
        if aspect == 1 { width = min(width, maxIconTile) }
        return (best.columns, max(minTileWidth, width.rounded(.down)))
    }
}
