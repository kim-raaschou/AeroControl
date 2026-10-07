import Testing
import CoreGraphics
@testable import Common

@Suite("GridWalk: the map as one grid")
struct GridWalkTests {
    // Cards A and B side by side, C under A; two by two windows in each.
    private func r(_ x: CGFloat, _ y: CGFloat) -> CGRect { CGRect(x: x, y: y, width: 90, height: 60) }
    private var frames: [Int: CGRect] {
        [1: r(0, 0), 2: r(100, 0), 3: r(0, 70), 4: r(100, 70), 5: r(220, 0), 6: r(320, 0), 7: r(220, 70), 8: r(320, 70),
         9: r(0, 160), 10: r(100, 160), 11: r(0, 230), 12: r(100, 230)]
    }
    private var cards: [GridWalk.Card] {
        let card = { (x: CGFloat, y: CGFloat, ids: [Int]) in (frame: CGRect(x: x, y: y, width: 200, height: 140), windows: frames.filter { ids.contains($0.key) }) }
        return [card(220, 0, [5, 6, 7, 8]), card(0, 0, [1, 2, 3, 4]), card(0, 160, [9, 10, 11, 12]), card(0, 320, [])]
    }
    private var lines: [[Int]] { GridWalk.lines(cards) }
    private func go(_ id: Int, _ x: CGFloat, _ y: CGFloat) -> Int? { GridWalk.step(from: id, rows: Int(y), lines: lines, frames: frames) }

    @Test("the lines run through every card of a lattice row, each card's own rows one after another; an empty card has none")
    func linesOfTheMap() {
        #expect(lines == [[1, 2, 5, 6], [3, 4, 7, 8], [9, 10], [11, 12]])
    }

    @Test("⌘↑ and ⌘↓ go to the card above or below, the nearest across, its first window; a row of empty cards is passed; past the top or bottom, nothing")
    func cardAbove() {
        func go(_ id: Int, _ d: Int) -> Int? { GridWalk.cardRow(from: id, direction: d, cards: cards) }
        #expect(go(6, 1) == 9 && go(11, -1) == 1 && go(2, -1) == nil && go(9, 1) == nil)
    }

    @Test("↑ and ↓ go to the line above or below, to the window nearest across, into the card under or over; past the top or bottom, nothing")
    func upAndDown() {
        #expect(go(1, 0, 1) == 3 && go(4, 0, 1) == 10 && go(8, 0, 1) == 10 && go(9, 0, -1) == 3 && go(7, 0, -1) == 5)
        #expect(go(1, 0, -1) == nil && go(12, 0, 1) == nil)
    }
}
