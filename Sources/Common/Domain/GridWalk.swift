import CoreGraphics

/// ↑ and ↓ read the map as one grid: the lattice's rows of cards top to bottom, and in each as
/// many lines as its tallest card has rows of windows, every line running left to right through
/// all the row's cards. So they keep to the column, into the card below or above.
public enum GridWalk {
    /// A card on the map: where the lattice put it, and its windows as drawn.
    public typealias Card = (frame: CGRect, windows: [Int: CGRect])

    /// The map's lines of windows, top to bottom; an empty card has none.
    public static func lines(_ cards: [Card]) -> [[Int]] {
        let lattice = Dictionary(grouping: cards.filter { !$0.windows.isEmpty }) { $0.frame.minY.rounded() }
            .sorted { $0.key < $1.key }.map { $0.value.sorted { $0.frame.minX < $1.frame.minX }.map(rows(of:)) }
        return lattice.flatMap { row in (0..<(row.map(\.count).max() ?? 0)).map { i in row.flatMap { $0.dropFirst(i).first ?? [] } } }
    }

    /// A card's windows in rows, top to bottom, each left to right: a window whose middle lies
    /// below the bottom of its row's first starts the next row.
    public static func rows(of card: Card) -> [[Int]] {
        var rows: [[Int]] = [], bottom = -CGFloat.infinity
        for (id, r) in card.windows.sorted(by: { ($0.value.midY, $0.value.minX) < ($1.value.midY, $1.value.minX) }) {
            if r.midY > bottom { rows.append([]); bottom = r.maxY }
            rows[rows.count - 1].append(id)
        }
        return rows.map { $0.sorted { card.windows[$0]!.minX < card.windows[$1]!.minX } }
    }

    /// ⌘↑ and ⌘↓: the first window, left of the top row, of the card above or below `id`'s
    /// (`direction` -1 or 1), the nearest across; a lattice row of empty cards is passed, and
    /// past the top or bottom it is nil.
    public static func cardRow(from id: Int, direction: Int, cards: [Card]) -> Int? {
        let held = cards.filter { !$0.windows.isEmpty }, levels = Set(held.map { $0.frame.minY.rounded() }).sorted()
        guard let at = held.first(where: { $0.windows[id] != nil }), let level = levels.firstIndex(of: at.frame.minY.rounded()),
              levels.indices.contains(level + direction) else { return nil }
        let below = held.filter { $0.frame.minY.rounded() == levels[level + direction] }.min { abs($0.frame.midX - at.frame.midX) < abs($1.frame.midX - at.frame.midX) }
        return below.flatMap { rows(of: $0).joined().first }
    }

    /// Where ↑ (`rows` -1) or ↓ (1) goes from `id`: to the line above or below, the window there
    /// nearest across, the left of two as near; nil past the top or bottom. Every window of the
    /// `lines` has its frame in `frames`.
    public static func step(from id: Int, rows d: Int, lines: [[Int]], frames: [Int: CGRect]) -> Int? {
        guard let line = lines.firstIndex(where: { $0.contains(id) }), lines.indices.contains(line + d) else { return nil }
        let key = { (w: Int) in (abs(frames[w]!.midX - frames[id]!.midX), frames[w]!.minX) }
        return lines[line + d].min { key($0) < key($1) }
    }
}
