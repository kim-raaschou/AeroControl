import Testing
import Foundation
@testable import Common

// The justified photo grid inside a card, ported from krn.overview's CardGeometry.js:
// every tile at its own aspect, one shared picture height, rows filled greedily and then
// spread evenly, an over-wide tile clamped to the card. Ratios are width / height.

private let gap: CGFloat = 8
private let caption: CGFloat = 18

private func pack(_ ratios: [CGFloat], height: CGFloat, width: CGFloat, scales: [CGFloat]? = nil) -> TilePacker.Packed {
    TilePacker.packRows(ratios: ratios, tileHeight: height, width: width, gap: gap, caption: caption, scales: scales)
}

private func overlap(_ tiles: [TilePacker.Tile]) -> (Int, Int)? {
    for i in tiles.indices {
        for j in tiles.indices where j > i {
            let a = tiles[i], b = tiles[j]
            if a.x < b.x + b.width && b.x < a.x + a.width && a.y < b.y + b.height && b.y < a.y + a.height { return (i, j) }
        }
    }
    return nil
}

@Suite("TilePacker.packRows")
struct PackRowsTests {
    @Test("a shorter row is centred under the wider one, not hung from the left")
    func shorterRowIsCentred() {
        // Five 150-wide tiles with 8 between them, in a 500-wide card, fall as 3 + 2: 466 wide over 308 wide.
        let r = pack(Array(repeating: 1.5, count: 5), height: 100, width: 500)
        #expect(r.rows == [[0, 1, 2], [3, 4]] && r.width == 466)
        #expect(r.tiles[0].x == 0 && r.tiles[1].x == 158 && r.tiles[2].x == 316)
        #expect(r.tiles[3].x == 79 && r.tiles[4].x == 237)              // (466 - 308) / 2 = 79
        #expect(r.tiles.allSatisfy { $0.x >= 0 && $0.x + $0.width <= r.width })
    }

    @Test("six mixed tiles: every one placed, none overlapping, inside the width, a caption under each")
    func placesEveryTile() {
        let ratios: [CGFloat] = [1.6, 1.6, 0.8, 2.4, 1.0, 1.33]
        let r = pack(ratios, height: 120, width: 900)
        #expect(r.tiles.count == ratios.count)
        #expect(overlap(r.tiles) == nil)
        #expect(r.tiles.allSatisfy { $0.x >= 0 && $0.x + $0.width <= 901 })
        #expect(r.width == r.tiles.map { $0.x + $0.width }.max())
        #expect(r.tiles.allSatisfy { $0.height > caption })
        #expect(r.rows.flatMap { $0 } == Array(ratios.indices))               // reading order, every index once
    }

    @Test("a tile too wide for the card is clamped to it and still gets a place")
    func clampsOverWide() {
        let r = pack([5.48, 1.0, 1.0], height: 200, width: 600)
        #expect(r.tiles.count == 3)
        #expect(r.tiles.allSatisfy { $0.width <= 600 })
    }

    @Test("a tile with a bigger scale is drawn bigger")
    func scales() {
        let r = pack([1.6, 1.6], height: 100, width: 2000, scales: [2.0, 0.5])
        #expect(r.tiles[0].width > r.tiles[1].width)
    }

    @Test("rows are spread evenly once their number is known: six alike are 3 + 3, not 4 + 2")
    func spreadsEvenly() {
        let r = pack(Array(repeating: 1.6, count: 6), height: 100, width: 4 * 160 + 3 * gap)
        #expect(r.rows.map(\.count) == [3, 3])
    }

    @Test("shorter tiles sit centred in a row as tall as its tallest")
    func centresInRow() {
        let r = pack([1.0, 1.0], height: 100, width: 300, scales: [1.0, 0.5])   // 100 tall beside 50 tall
        #expect(r.rows.count == 1)
        #expect(r.tiles[1].y == 25 && r.tiles[0].y == 0)
    }
}

@Suite("TilePacker.packHeight")
struct PackHeightTests {
    static let cases: [(ratios: [CGFloat], width: CGFloat, height: CGFloat)] = [
        ([1.6, 1.6, 0.8, 2.4, 1.0, 1.33], 900, 500),
        ([1.78], 400, 300),
        ([1.0, 1.0, 1.0, 1.0], 640, 480),
        ([5.48, 0.6, 1.6, 1.6, 1.6, 0.9, 2.2, 1.1], 1200, 700),
        ([0.5, 0.5, 0.5], 300, 900),
    ]

    @Test("the largest shared height that still fits: usable, fitting, non-overlapping, and maximal", arguments: cases.indices)
    func maximal(index: Int) {
        let c = Self.cases[index]
        let th = TilePacker.packHeight(ratios: c.ratios, width: c.width, height: c.height, gap: gap, caption: caption, scales: nil)
        #expect(th >= 1)
        let fit = pack(c.ratios, height: th, width: c.width)
        #expect(fit.width <= c.width + 1 && fit.height <= c.height + 1)
        #expect(overlap(fit.tiles) == nil)
        // One more pixel must either not fit or draw nothing bigger — past the over-wide
        // clamp a taller height buys nothing, but a taller height that fits AND draws
        // bigger is space left unused.
        let over = pack(c.ratios, height: th + 1, width: c.width)
        let drawn = { (p: TilePacker.Packed) in p.tiles.map { $0.width * ($0.height - caption) }.max() ?? 0 }
        #expect(over.width > c.width + 1 || over.height > c.height + 1 || drawn(over) <= drawn(fit))
    }

    @Test("nothing to pack is height 0")
    func empty() {
        #expect(TilePacker.packHeight(ratios: [], width: 100, height: 100, gap: gap, caption: caption, scales: nil) == 0)
        #expect(TilePacker.packHeight(ratios: [1.5], width: 0, height: 100, gap: gap, caption: caption, scales: nil) == 0)
    }
}
