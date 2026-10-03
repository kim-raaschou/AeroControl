import Testing
import Foundation
@testable import Common

// What is left of the tree engine: the layout's own order, read from AeroSpace's rects, for the
// ring, the keys and the strip. The reconstruction from sizes went on 2026-10-03: it inferred
// what AeroSpace had not said, and the rects say it.

fileprivate typealias T = WorkspaceTree

@Suite("WorkspaceTree.order: the layout's own order from AeroSpace's rects")
struct WorkspaceTreeOrderTests {
    private func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }

    @Test("side by side: left to right, whatever order AeroSpace listed them in")
    func sideBySide() {
        // The owner's workspace 4: Ghostty listed first, standing on the right of Mail.
        #expect(T.order([(10916, r(1726, 48, 1698, 1375)), (10776, r(16, 48, 1698, 1375))]) == [10776, 10916])
    }

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

    @Test("rects that overlap, an accordion's, keep the order they came in")
    func overlapKeepsOrder() {
        #expect(T.order([(2, r(46, 48, 1636, 1052)), (1, r(16, 48, 1696, 1052))]) == [2, 1])
    }
}
