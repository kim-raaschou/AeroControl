import Testing
import Foundation
@testable import Common

// The cards on the screen: one identical, screen-shaped cell per workspace in a lattice, the
// lattice that gives the largest cell, centred in the box, the last row left-aligned. What
// GNOME Shell and KWin do; chosen over the row-break search on 2026-09-30 (see
// docs/outer-grid-literature.md).

private let box = CGSize(width: 1624, height: 994)
private let screen: CGFloat = 1.547
private let gap: CGFloat = 24

/// What a card spends on its header and padding: the inner box is the cell less this.
private let chrome = CGSize(width: 36, height: 76)
private func lattice(_ n: Int) -> CardGrid.Layout { CardGrid.lattice(count: n, in: box, cellRatio: screen, gap: gap, chrome: chrome) }

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

@Suite("CardGrid.lattice")
struct CardGridTests {
    @Test("every card placed, inside the box, none overlapping, in order, all the same size", arguments: [1, 2, 3, 4, 5, 6, 7, 9, 10, 12, 16])
    func invariants(n: Int) {
        let g = lattice(n)
        #expect(g.cells.count == n && g.cells.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })
        #expect(g.cells.allSatisfy { $0.frame.minX >= 0 && $0.frame.minY >= 0 && $0.frame.maxX <= box.width + 1 && $0.frame.maxY <= box.height + 1 })
        #expect(overlap(g.cells.map(\.frame)) == nil)
        #expect(g.cells.map(\.index) == Array(0..<n))
        #expect(g.rows.flatMap { $0 } == Array(0..<n))
        #expect(Set(g.cells.map { $0.frame.size }).count == 1)
    }

    @Test("a cell's inner box, the cell less its chrome, has the screen's shape, so a drawn screen fills it", arguments: [1, 3, 7, 12])
    func innerBoxHasScreenShape(n: Int) {
        let size = lattice(n).cells[0].frame.size
        #expect(abs((size.width - chrome.width) / (size.height - chrome.height) - screen) < 0.01)
    }

    @Test("without chrome the cell itself has the screen's shape")
    func cellShapeWithoutChrome() {
        let size = CardGrid.lattice(count: 7, in: box, cellRatio: screen, gap: gap).cells[0].frame.size
        #expect(abs(size.width / size.height - screen) < 0.01)
    }

    @Test("the lattice with the largest cell wins", arguments: [
        (2, "1 2"),
        (4, "1 2 | 3 4"),
        (7, "1 2 3 | 4 5 6 | 7"),                 // the owner's seven: a 3 × 3 with two holes
        (8, "1 2 3 | 4 5 6 | 7 8"),
        (12, "1 2 3 4 | 5 6 7 8 | 9 10 11 12"),
    ])
    func largestCell(n: Int, expected: String) {
        #expect(shape(lattice(n)) == expected)
    }

    @Test("rows start at the same x, so a short last row is left-aligned with holes at its end")
    func rowsAligned() {
        let g = lattice(7)
        #expect(g.cells[0].frame.minX == g.cells[3].frame.minX && g.cells[3].frame.minX == g.cells[6].frame.minX)
        #expect(g.cells[0].frame.minY == g.cells[1].frame.minY && g.cells[3].frame.minY > g.cells[0].frame.maxY)
    }

    @Test("the whole lattice sits centred in the box")
    func centred() {
        let g = lattice(7)
        let frames = g.cells.map(\.frame)
        let minX = frames.map(\.minX).min()!, maxX = frames.map(\.minX).max()! + frames[0].width
        let minY = frames.map(\.minY).min()!, maxY = frames.map(\.maxY).max()!
        #expect(abs(minX - (box.width - maxX)) <= 1)
        #expect(abs(minY - (box.height - maxY)) <= 1)
    }

    @Test("nothing to lay out survives, and so does a zero-sized box")
    func degenerate() {
        let none = CardGrid.lattice(count: 0, in: box, cellRatio: screen, gap: gap)
        #expect(none.cells.isEmpty && none.rows.isEmpty)
        let flat = CardGrid.lattice(count: 3, in: .zero, cellRatio: screen, gap: gap)
        #expect(flat.cells.count == 3 && flat.rows == [[0, 1, 2]])
    }
}
