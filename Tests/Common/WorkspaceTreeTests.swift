import Testing
import Foundation
@testable import Common

// What is left of the tree engine: the layout's own order, read from AeroSpace's rects, for the
// ring, the keys and the strip. The reconstruction from sizes went on 2026-10-03: it inferred
// what AeroSpace had not said, and the rects say it.

fileprivate typealias T = WorkspaceTree

@Suite("WorkspaceTree: AeroSpace's tree read from its rects — the layout's own order, and the tree at its shape in a box")
struct WorkspaceTreeOrderTests {
    private func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

    @Test("a column of four beside a tall window: the column top to bottom, then the window, as AeroSpace's tree has them")
    func columnThenWindow() {
        let rects = [(8266, r(870, 48, 842, 1052)), (5022, r(16, 843, 842, 257)), (8243, r(16, 48, 842, 257)),
                     (3352, r(16, 580, 842, 251)), (8240, r(16, 317, 842, 251))]
        #expect(T.order(rects) == [8243, 8240, 3352, 5022, 8266])
    }

    @Test("a row of four over one wide window: the row left to right, then the wide one")
    func rowOverWide() {
        let rects = [(10730, r(16, 742, 3408, 682)), (10727, r(2578, 48, 846, 682)), (8240, r(16, 48, 846, 682)),
                     (10724, r(1726, 48, 840, 682)), (10721, r(874, 48, 840, 682))]
        #expect(T.order(rects) == [8240, 10721, 10724, 10727, 10730])
    }

    @Test("in a box, every window at its own shape and the parts of a split sharing the side across it, a gap between, in the layout's order whatever order AeroSpace listed them in: a column beside two stacked is the column's 330:1052 beside the pair's 1354:1040, as high as each other; rects that overlap, an accordion's, all take the whole box and keep the order they came in")
    func shapedInABox() {
        let laid = T.shaped([(2, r(358, 49, 1354, 520)), (1, r(16, 49, 330, 1052)), (3, r(358, 581, 1354, 520))], in: r(10, 20, 610, 410), gap: 10)
        #expect(laid.map(\.0) == [1, 2, 3] && laid.map(\.1) == [r(10, 20, 116, 410), r(136, 20, 484, 200), r(136, 230, 484, 200)])
        let accordion = T.shaped([(2, r(46, 48, 1636, 1052)), (1, r(16, 48, 1696, 1052))], in: r(0, 0, 50, 40), gap: 4)
        #expect(accordion.map(\.0) == [2, 1] && accordion.map(\.1) == [r(0, 0, 50, 40), r(0, 0, 50, 40)])
    }
}
