import Common
import CoreGraphics

/// Pure layout math for the full-screen overview, Mission-Control style: the grid is the
/// same shape whatever the workspaces hold. Cards are split into rows of as equal length
/// as possible, every row is the same height, and within a row every card that holds
/// windows is the same width (empty workspaces keep a badge-wide sliver). A card's windows
/// are packed by `TilePacker`: each at its own shape, one shared picture height. All
/// unit-tested.
public enum AeroControlLayout {
    public static let usableScreenFraction: CGFloat = 0.94
    public static let cardGap: CGFloat = 24
    public static let tileSpacing: CGFloat = 14
    public static let cardPadding: CGFloat = 18
    /// Vertical room reserved at the top of a card for the workspace badge.
    public static let badgeLane: CGFloat = 44
    /// Diameter of the workspace badge in the card header.
    public static let badgeSize: CGFloat = 24
    /// An empty card is exactly the badge plus the card padding on both sides, so the badge
    /// sits in the same corner as on full cards and is centered in the narrow card as well.
    public static let emptyCardWidth: CGFloat = badgeSize + 2 * cardPadding
    /// Wider empty card: room for the badge AND the display name beside it, used when the
    /// workspaces span more than one display.
    public static let namedEmptyCardWidth: CGFloat = emptyCardWidth + 82
    /// While a filter is up each tile carries a caption above its picture: a title line and
    /// the gap to the picture. Both the tile and `usedHeight` budget for it from here.
    public static let captionTitleHeight: CGFloat = 32
    public static let captionGap: CGFloat = 6
    public static let captionLane: CGFloat = captionTitleHeight + captionGap

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

    /// The room inside a card for its tiles: below the badge lane, inside the padding.
    public static func innerSize(of card: CGSize) -> CGSize {
        CGSize(width: card.width - 2 * cardPadding, height: card.height - cardPadding - badgeLane)
    }

    /// A card's tiles as drawn: `TilePacker` at the largest picture height that fits `inner`,
    /// with `caption` under each tile (the caption lane while filtering, nothing on the map).
    public static func packTiles(ratios: [CGFloat], inner: CGSize, caption: CGFloat) -> TilePacker.Packed {
        let height = TilePacker.packHeight(ratios: ratios, width: inner.width, height: inner.height,
                                           gap: tileSpacing, caption: caption, scales: nil)
        return TilePacker.packRows(ratios: ratios, tileHeight: max(1, height), width: inner.width,
                                   gap: tileSpacing, caption: caption, scales: nil)
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

    /// The height a row of cards can actually use. A picture cannot grow past its own shape,
    /// so a card taller than its tiles need is height it will only ever leave empty — with
    /// two matches on a wide screen that is most of the screen. Only the filtered grid uses
    /// this, with the caption lane every filtered tile wears.
    ///
    /// The map keeps its even rows on purpose: a workspace must sit in the same place whatever
    /// it happens to contain, and a height that followed the content would move it every time
    /// a window opened.
    public static func usedHeight(ratiosPerCard: [[CGFloat]], widths: [CGFloat], caption: CGFloat,
                                  available: CGFloat) -> CGFloat {
        let needed = ratiosPerCard.indices.map { i -> CGFloat in
            guard !ratiosPerCard[i].isEmpty else { return 0 }
            let inner = innerSize(of: CGSize(width: widths[i], height: available))
            return packTiles(ratios: ratiosPerCard[i], inner: inner, caption: caption).height + cardPadding + badgeLane
        }
        return min(available, needed.max() ?? available)
    }
}
