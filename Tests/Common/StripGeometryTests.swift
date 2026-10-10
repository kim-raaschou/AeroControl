import Testing
import CoreGraphics
@testable import Common

@Suite("StripGeometry")
struct StripGeometryTests {
    private typealias M = StripGeometry
    @Test("one card fills the view's width, up to most of the panel; more each take a 3.5th of it, up to a third of the panel")
    func cardHeight() {
        // A 1728 x 1085 screen (1.6), 24 of chrome round each card.
        func h(_ cards: Int, _ view: CGFloat = 1900) -> CGFloat { M.cardHeight(view: view, cards: cards, aspect: 1.6, chrome: 24, panelHeight: 1085) }
        #expect(h(1) == (1085 * M.tallest).rounded() && h(2) == (1085 * M.tallestOfSeveral).rounded() && h(5) == ((1900 / M.seen - 24) / 1.6).rounded(.down))
        #expect(h(5, 900) == ((900 / M.seen - 24) / 1.6).rounded(.down) && h(3, 900) == ((900 / 3 - 24) / 1.6).rounded(.down))   // three fit whole              // a narrow view: the neighbours cut by its edges
    }

}
