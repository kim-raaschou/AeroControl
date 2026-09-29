import Testing
import Foundation
@testable import Common

// The cards on the screen, ported from krn.overview's `weightedCells`: widths by weight
// (empty = a strip, ordinary = 1, crowded = 2), rows broken where the windows come out
// largest, row heights that follow what the row has to show, the whole thing centred.

private func slot(_ count: Int) -> CardGrid.Slot {
    CardGrid.Slot(weight: count == 0 ? 0 : (count >= 4 ? 2 : 1), count: count)
}

private func overlap(_ frames: [CGRect]) -> (Int, Int)? {
    for i in frames.indices {
        for j in frames.indices where j > i {
            if frames[i].intersects(frames[j]) && frames[i].intersection(frames[j]).width > 0.5
                && frames[i].intersection(frames[j]).height > 0.5 { return (i, j) }
        }
    }
    return nil
}

/// The rows as "1 2 3 | 4 5", reading the cells' y.
private func shape(_ layout: CardGrid.Layout) -> String {
    layout.rows.map { $0.map { String($0 + 1) }.joined(separator: " ") }.joined(separator: " | ")
}

// krn.overview's two option sets: the generic one, and the one measured on a 1900x1000 screen.
private let generic = CardGrid.Options(gap: 10, tileRatio: 16 / 9, cardPadding: 8, chrome: 40, narrow: 120, tileGap: 8, caption: 18)
private let measured = CardGrid.Options(gap: 16, tileRatio: 1.6, cardPadding: 12, chrome: 68, narrow: 180, tileGap: 12, caption: 24)

@Suite("CardGrid")
struct CardGridTests {
    @Test("every card placed, inside the box, none overlapping, in order", arguments: [1, 2, 3, 4, 5, 6, 7, 9, 10, 12])
    func invariants(n: Int) {
        let g = CardGrid.layout(Array(repeating: slot(2), count: n), in: CGSize(width: 1900, height: 1000), options: generic)
        #expect(g.cells.count == n && g.cells.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
        #expect(g.cells.allSatisfy { $0.frame.minX >= 0 && $0.frame.minY >= 0 && $0.frame.maxX <= 1901 && $0.frame.maxY <= 1001 })
        #expect(overlap(g.cells.map(\.frame)) == nil)
        #expect(g.cells.map(\.index) == Array(0..<n))
        #expect(g.rows.flatMap { $0 } == Array(0..<n))
    }

    @Test("rows break where the windows come out largest, and keep the default shape for a gain under 5 %", arguments: [
        ([1, 2, 0, 0, 0], "1 | 2 3 4 5", 398),          // one window in ws 1 and two in ws 2: ws 1 gets a row of its own
        ([3, 0, 0, 0, 0], "1 | 2 3 4 5", 385),          // windows only in ws 1: it gets the whole top row
        ([2, 2, 0, 2, 2], "1 2 3 | 4 5", 254),          // an empty ws 3 between busy ones stands beside them
        ([1, 4, 0, 0, 0], "1 2 3 | 4 5", 336),          // a gain under 5 % keeps the default shape
        ([2, 2, 2, 2, 2, 2], "1 2 | 3 4 | 5 6", 230),   // six busy workspaces stand 2 + 2 + 2
        ([2, 0, 0, 0, 2], "1 2 3 | 4 5", 0),            // empty 2–4 between two busy ones stand beside them
    ])
    func rowBreaks(counts: [Int], expected: String, smallest: Int) {
        let g = CardGrid.layout(counts.map(slot), in: CGSize(width: 1900, height: 1000), options: measured)
        #expect(shape(g) == expected)
        if smallest > 0 { #expect(Int(g.smallest.rounded()) == smallest) }
    }

    @Test("an empty card is the narrowest on its row; a crowded one is wider than an ordinary one")
    func widthsByWeight() {
        let g = CardGrid.layout([slot(0), slot(9), slot(2)], in: CGSize(width: 1900, height: 1000), options: generic)
        let w = g.cells.map(\.frame.width)
        #expect(w[0] <= w[1] && w[0] <= w[2])
        #expect(w[1] > w[2])
    }

    @Test("a break the search chose never stands a card upright", arguments: [2, 3, 4, 5, 6, 7, 8, 9, 10])
    func neverUpright(n: Int) {
        let slots = Array(repeating: slot(2), count: n)
        let chosen = CardGrid.layout(slots, in: CGSize(width: 1900, height: 1000), options: measured)
        var noSearch = measured
        noSearch.rowGain = .infinity
        let fallback = CardGrid.layout(slots, in: CGSize(width: 1900, height: 1000), options: noSearch)
        let moved = chosen.cells != fallback.cells
        #expect(!moved || chosen.cells.allSatisfy { $0.frame.width >= $0.frame.height })
    }

    @Test("no row of empty workspaces cuts the busy ones apart; the cards keep their order")
    func emptiesNeverCut() {
        // The overview as it stood on 2026-09-27: 1 (three windows), 2 empty, 3 (four, so it
        // weighs double), 4 empty, 5 empty, 8, 10 and the scratchpad.
        let counts = [3, 0, 4, 0, 0, 2, 1, 2]
        let opts = CardGrid.Options(gap: 8, tileRatio: 1728 / 1055, cardPadding: 6, chrome: 39, narrow: 90, tileGap: 6, caption: 17)
        let g = CardGrid.layout(counts.map(slot), in: CGSize(width: 1672, height: 948), options: opts)
        let busy = g.rows.map { $0.contains { counts[$0] > 0 } }
        let cut = busy.indices.contains { i in !busy[i] && busy[..<i].contains(true) && busy[(i + 1)...].contains(true) }
        #expect(!cut)
        #expect(g.rows.flatMap { $0 } == Array(0..<8))
    }

    @Test("rows use the height and sit centred: the first starts where the last ends short of the box")
    func centred() {
        let g = CardGrid.layout([1, 2, 0, 0, 0].map(slot), in: CGSize(width: 1900, height: 1000), options: measured)
        let top = g.cells.map(\.frame.minY).min()!
        let bottom = g.cells.map(\.frame.maxY).max()!
        #expect(abs(top - (1000 - bottom)) <= 1)
    }

    @Test("nothing to lay out survives, and so does a zero-sized box")
    func degenerate() {
        #expect(CardGrid.layout([], in: CGSize(width: 100, height: 100), options: generic).cells.isEmpty)
        #expect(CardGrid.layout([slot(1)], in: .zero, options: generic).cells.count == 1)
    }
}
