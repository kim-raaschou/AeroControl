import CoreGraphics

public enum GridWalk {
    public typealias Card = (frame: CGRect, windows: [Int: CGRect])

    public static func rows(of card: Card) -> [[Int]] {
        var rows: [[Int]] = [], bottom = -CGFloat.infinity
        for (id, r) in card.windows.sorted(by: { ($0.value.midY, $0.value.minX) < ($1.value.midY, $1.value.minX) }) {
            if r.midY > bottom { rows.append([]); bottom = r.maxY }
            rows[rows.count - 1].append(id)
        }
        return rows.map { $0.sorted { card.windows[$0]!.minX < card.windows[$1]!.minX } }
    }

    public static func step(from id: Int, rows d: Int, frames: [Int: CGRect]) -> Int? {
        guard let at = frames[id] else { return nil }
        let inLine = { (r: CGRect) in min(1, max(0, min(r.maxX, at.maxX) - max(r.minX, at.minX))) }
        let key = { (r: CGRect) in (-inLine(r), abs(r.midY - at.midY), abs(r.midX - at.midX), r.minX) }
        return frames.filter { ($0.value.midY - at.midY) * CGFloat(d) > at.height / 2 }.min { key($0.value) < key($1.value) }?.key
    }

    public static func step(from id: Int, columns d: Int, frames: [Int: CGRect]) -> Int? {
        guard let at = frames[id] else { return nil }
        let level = frames.filter { min($0.value.maxY, at.maxY) > max($0.value.minY, at.minY) }
        return step(from: id, rows: d, frames: level.mapValues { CGRect(x: $0.minY, y: $0.minX, width: $0.height, height: $0.width) })
    }
}
