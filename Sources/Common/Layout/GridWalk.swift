import CoreGraphics

/// The keys on the map and the strip, as their windows are drawn: a card's windows in rows for ←
/// and →, straight up and down for ↑ and ↓, a card's row for ⌘↑ and ⌘↓.
public enum GridWalk {
    /// A card on the map: where the lattice put it, and its windows as drawn.
    public typealias Card = (frame: CGRect, windows: [Int: CGRect])

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
    /// (`direction` -1 or 1), the nearest across; a lattice row of empty cards is passed, and past
    /// the top or bottom it is nil.
    public static func cardRow(from id: Int, direction: Int, cards: [Card]) -> Int? {
        let held = cards.filter { !$0.windows.isEmpty }, levels = Set(held.map { $0.frame.minY.rounded() }).sorted()
        guard let at = held.first(where: { $0.windows[id] != nil }), let level = levels.firstIndex(of: at.frame.minY.rounded()),
              levels.indices.contains(level + direction) else { return nil }
        let below = held.filter { $0.frame.minY.rounded() == levels[level + direction] }.min { abs($0.frame.midX - at.frame.midX) < abs($1.frame.midX - at.frame.midX) }
        return below.flatMap { rows(of: $0).joined().first }
    }

    /// Where ↑ (`rows` -1) or ↓ (1) goes from `id`: straight up or down as drawn, to the nearest
    /// window over or under it, the nearest across, the left of two as near; with none straight
    /// there, the nearest aslant; nil past the top or bottom.
    public static func step(from id: Int, rows d: Int, frames: [Int: CGRect]) -> Int? {
        guard let at = frames[id] else { return nil }
        let inLine = { (r: CGRect) in min(1, max(0, min(r.maxX, at.maxX) - max(r.minX, at.minX))) }   // 1 when it overlaps across, else 0
        let key = { (r: CGRect) in (-inLine(r), abs(r.midY - at.midY), abs(r.midX - at.midX), r.minX) }
        return frames.filter { ($0.value.midY - at.midY) * CGFloat(d) > at.height / 2 }.min { key($0.value) < key($1.value) }?.key
    }
}
