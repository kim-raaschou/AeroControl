import CoreGraphics

/// Pure layout math for the full-screen overview, Mission-Control style: the grid is the
/// same shape whatever the workspaces hold. Cards are split into rows of as equal length
/// as possible, every row is the same height, and within a row every card that holds
/// windows is the same width (empty workspaces keep a badge-wide sliver). A card's windows
/// fill it as a grid of 3:2 tiles (or square icons) using whichever column count yields
/// the largest tiles. All unit-tested.
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
    /// Diameter of the workspace badge in the card header.
    public static let badgeSize: CGFloat = 24
    /// An empty card is exactly the badge plus the card padding on both sides, so the badge
    /// sits in the same corner as on full cards and is centered in the narrow card as well.
    public static let emptyCardWidth: CGFloat = badgeSize + 2 * cardPadding
    /// Wider empty card: room for the badge AND the display name beside it, used when the
    /// workspaces span more than one display.
    public static let namedEmptyCardWidth: CGFloat = emptyCardWidth + 82

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

    /// Splits `count` cards into `rowCount` contiguous rows of as equal length as possible,
    /// order preserved; a remainder goes to the top rows (7 in 3 rows → 3, 2, 2).
    public static func partition(count: Int, rowCount: Int) -> [Range<Int>] {
        guard rowCount > 0, count > 0 else { return [] }
        let rows = min(rowCount, count)
        let (length, remainder) = (count / rows, count % rows)
        var result: [Range<Int>] = []
        var start = 0
        for row in 0..<rows {
            let end = start + length + (row < remainder ? 1 : 0)
            result.append(start..<end)
            start = end
        }
        return result
    }

    /// Snapshot cells are shaped like the screen when nothing better is known.
    public static func previewAspect(for available: CGSize) -> CGFloat {
        available.width > 0 ? available.height / available.width : tileAspect
    }

    /// Cell aspect (height/width) for one workspace: the median of its snapshots' aspects,
    /// so four tall columns get tall cells and one full-width window a wide one. Mixed
    /// workspaces get a middle ground; every snapshot still fits inside its cell.
    public static func cellAspect(snapshotSizes: [CGSize], fallback: CGFloat) -> CGFloat {
        let aspects = snapshotSizes.filter { $0.width > 0 && $0.height > 0 }.map { $0.height / $0.width }.sorted()
        guard !aspects.isEmpty else { return fallback }
        return aspects[aspects.count / 2]
    }

    /// One card in a laid-out row: which workspace it is (an index into `windowCounts`) and
    /// how big it is. Carrying the index means the caller never has to re-derive the row
    /// split to know whose card it is holding.
    public struct Cell: Equatable, Identifiable {
        public let index: Int
        public let size: CGSize
        public var id: Int { index }
    }

    /// Cards per row for `windowCounts` (in AeroSpace order) inside `available`: even rows,
    /// equal row heights, equal widths for the cards that hold windows.
    public static func cardRows(windowCounts: [Int], emptyWidth: CGFloat = emptyCardWidth,
                                available: CGSize) -> [[Cell]] {
        let count = windowCounts.count
        guard count > 0, available.width > 0, available.height > 0 else { return [] }
        let rows = partition(count: count, rowCount: rowCount(forCount: count))
        let height = ((available.height - CGFloat(rows.count - 1) * cardGap) / CGFloat(rows.count)).rounded(.down)
        return rows.map { range in
            let widths = rowWidths(windowCounts: Array(windowCounts[range]),
                                   rowWidth: available.width, emptyWidth: emptyWidth)
            return zip(range, widths).map { Cell(index: $0, size: CGSize(width: $1, height: height)) }
        }
    }

    /// Just the sizes, for the layout tests and anything that does not need the identity.
    public static func cardSizes(windowCounts: [Int], emptyWidth: CGFloat = emptyCardWidth,
                                 available: CGSize) -> [[CGSize]] {
        cardRows(windowCounts: windowCounts, emptyWidth: emptyWidth, available: available)
            .map { $0.map(\.size) }
    }

    /// Widths inside one row: empty workspaces take `emptyWidth`, the cards that hold
    /// windows split what is left equally, so a card's size never depends on its neighbours.
    static func rowWidths(windowCounts: [Int], rowWidth: CGFloat, emptyWidth: CGFloat = emptyCardWidth) -> [CGFloat] {
        let usable = rowWidth - CGFloat(windowCounts.count - 1) * cardGap
        let filled = windowCounts.count { $0 > 0 }
        guard filled > 0 else {
            return windowCounts.map { _ in (usable / CGFloat(windowCounts.count)).rounded(.down) }
        }
        let empties = CGFloat(windowCounts.count - filled) * emptyWidth
        let each = max(0, (usable - empties) / CGFloat(filled)).rounded(.down)
        return windowCounts.map { $0 > 0 ? each : emptyWidth }
    }

    /// The height a row of cards can actually use. A snapshot cannot grow past its own aspect
    /// ratio, so a card taller than its tiles need is height it will only ever leave empty —
    /// with two matches on a wide screen that is most of the screen.
    ///
    /// Only the filtered grid uses this. The map keeps its even rows on purpose: a workspace
    /// must sit in the same place whatever it happens to contain, and a height that followed
    /// the content would move it every time a window opened.
    public static func usedHeight(windowCounts: [Int], widths: [CGFloat], aspects: [CGFloat],
                                  available: CGFloat) -> CGFloat {
        let needed = windowCounts.indices.map { i -> CGFloat in
            guard windowCounts[i] > 0 else { return 0 }
            let card = CGSize(width: widths[i], height: available)
            let (columns, tile) = tileGrid(windowCount: windowCounts[i], card: card, aspect: aspects[i])
            let rows = CGFloat(Int((Double(windowCounts[i]) / Double(columns)).rounded(.up)))
            return rows * tile * aspects[i] + (rows - 1) * tileSpacing + cardPadding + badgeLane
        }
        return min(available, needed.max() ?? available)
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
