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
    /// Width of an empty workspace's card: just the badge.
    public static let emptyCardWidth: CGFloat = 84
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
    public static func cardSizes(windowCounts: [Int], available: CGSize) -> [[CGSize]] {
        let n = windowCounts.count
        guard n > 0, available.width > 0, available.height > 0 else { return [] }
        let weights = windowCounts.map(weight(windowCount:))
        let rows = partition(weights: weights, rowCount: rowCount(forCount: n))
        let heights = rowHeights(rowWeights: rows.map { weights[$0].reduce(0, +) }, totalHeight: available.height)
        return zip(rows, heights).map { range, height in
            let counts = Array(windowCounts[range])
            let widths = rowWidths(windowCounts: counts, rowWidth: available.width)
            return widths.map { CGSize(width: $0, height: height) }
        }
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

    /// Column count and tile width that make `windowCount` tiles as large as possible
    /// inside the card's inner area. `aspect` is height/width: `tileAspect` or 1 (icons).
    public static func tileGrid(windowCount: Int, card: CGSize, aspect: CGFloat = tileAspect) -> (columns: Int, width: CGFloat) {
        guard windowCount > 0 else { return (0, 0) }
        let innerWidth = card.width - 2 * cardPadding
        let innerHeight = card.height - cardPadding - badgeLane
        var best = (columns: 1, width: CGFloat(0))
        for columns in 1...windowCount {
            let rows = Int((Double(windowCount) / Double(columns)).rounded(.up))
            let byWidth = (innerWidth - CGFloat(columns - 1) * tileSpacing) / CGFloat(columns)
            let byHeight = ((innerHeight - CGFloat(rows - 1) * tileSpacing) / CGFloat(rows)) / aspect
            let width = min(byWidth, byHeight)
            if width > best.width { best = (columns, width) }
        }
        var width = best.width
        if aspect == 1 { width = min(width, maxIconTile) }
        return (best.columns, max(minTileWidth, width.rounded(.down)))
    }
}
