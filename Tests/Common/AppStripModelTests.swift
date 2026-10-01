import Testing
import CoreGraphics
@testable import Common

// The strip's rules, ported from krn.overview's AppStripModel.js and its tests
// (test/app-strip-model.test.js): stepping, the first marking, the ring, the card height,
// the frames, and the keys. One difference by decision: the marking only chooses, it does not
// focus, so nothing here waits on a focus request.

private typealias M = AppStripModel

@Suite("AppStripModel: stepping")
struct AppStripStepTests {
    @Test("stepping wraps round, starts at the near end without a marking, and selects nothing in an empty strip")
    func stepIndex() {
        #expect(M.stepIndex(3, count: 4, direction: 1) == 0)
        #expect(M.stepIndex(0, count: 4, direction: -1) == 3)
        #expect(M.stepIndex(-1, count: 4, direction: 1) == 0 && M.stepIndex(-1, count: 4, direction: -1) == 3)
        #expect(M.stepIndex(0, count: 0, direction: 1) == -1)
    }

    @Test("the marking opens on the window after the one you are in; with two, on the other; from outside the app, on the first")
    func start() {
        #expect(M.start(origin: 2, ids: [1, 2, 3]) == 3)
        #expect(M.start(origin: 3, ids: [1, 2, 3]) == 1)
        #expect(M.start(origin: 1, ids: [1, 2]) == 2 && M.start(origin: 2, ids: [1, 2]) == 1)
        #expect(M.start(origin: 9, ids: [1, 2, 3]) == 1 && M.start(origin: nil, ids: [1, 2]) == 1)
        #expect(M.start(origin: 1, ids: []) == nil)
    }

    @Test("the marked window keeps the marking when others move; a closed one hands it to its successor")
    func keepSelection() {
        #expect(M.keepSelection(3, lastIndex: 0, ids: [1, 2, 3]) == 3)
        #expect(M.keepSelection(9, lastIndex: 1, ids: [1, 3]) == 3)
        #expect(M.keepSelection(9, lastIndex: 5, ids: [1, 3]) == 3)
        #expect(M.keepSelection(1, lastIndex: 0, ids: []) == nil)
    }

    @Test("steps pass over a window that cannot be picked, round the end, and stay put when nothing else can")
    func stepPickable() {
        #expect(M.stepPickable(0, pickable: [true, false, true], direction: 1) == 2)
        #expect(M.stepPickable(0, pickable: [true, true, false], direction: -1) == 1)
        #expect(M.stepPickable(-1, pickable: [false, true, true], direction: 1) == 1)
        #expect(M.stepPickable(0, pickable: [true, false, false], direction: 1) == 0)
        #expect(M.stepPickable(0, pickable: [false, false], direction: 1) == -1)
    }
}

@Suite("AppStripModel: geometry")
struct AppStripGeometryTests {
    @Test("cards are as tall as the width allows, up to half the panel and never below a fifth")
    func cardHeight() {
        // A 1728 x 1085 screen, a view 1900 wide, cards the screen's shape (1.6).
        func h(_ cards: Int) -> CGFloat { M.cardHeight(width: 1900, gaps: 8 * CGFloat(cards - 1), sumAspect: 1.6 * CGFloat(cards), panelHeight: 1085) }
        #expect(h(5) == ((1900 - 32) / 8).rounded(.down))
        #expect(h(2) == (1085 * 0.5).rounded())
        #expect(M.cardHeight(width: 400, gaps: 80, sumAspect: 16, panelHeight: 1085) == (1085 * 0.2).rounded())
    }

    @Test("when the cards do not fit the view the row is a ring: the marked card in the middle, the last right before the first")
    func ring() {
        // Three cards of 100 with gaps of 10: a ring of 330.
        let spans = [M.Span(x: 0, width: 100), M.Span(x: 110, width: 100), M.Span(x: 220, width: 100)]
        func at(_ s: [CGFloat], _ g: Int) -> CGFloat { spans[g].x + s[g] }
        let s0 = M.ringShifts(spans, anchor: 50, centre: 150, ring: 330, view: 300)
        #expect(at(s0, 0) + 50 == 150)
        #expect(at(s0, 2) == at(s0, 0) - 110)
        #expect(at(s0, 1) == at(s0, 0) + 110)
        let s2 = M.ringShifts(spans, anchor: 270, centre: 150, ring: 330, view: 300)
        #expect(at(s2, 0) == at(s2, 2) + 110)
    }

    @Test("when every card fits, the row stands still, centred, in workspace order, whichever card is marked")
    func still() {
        let spans = [M.Span(x: 0, width: 100), M.Span(x: 110, width: 100), M.Span(x: 220, width: 100)]
        let still = [50, 160, 270].map { M.ringShifts(spans, anchor: CGFloat($0), centre: 500, ring: 330, view: 1000) }
        #expect(spans[0].x + still[0][0] == 340 && spans[2].x + still[0][2] + 100 == 660)
        #expect(still.allSatisfy { $0 == still[0] })
        #expect(M.ringShifts([], anchor: 0, centre: 0, ring: 0, view: 0).isEmpty)
        // Asked to run round always, a row that fits runs round too: the marked card in the middle.
        let round = M.ringShifts(spans, anchor: 270, centre: 500, ring: 330, view: 1000, alwaysRound: true)
        #expect(spans[2].x + round[2] + 50 == 500 && spans[0].x + round[0] == spans[2].x + round[2] + 110)
    }

    @Test("the marked window wears the accent, the window you came from the plain frame of where you are, and the marking wins")
    func frames() {
        #expect(M.frame(2, marked: 2, origin: 1) == .marked)
        #expect(M.frame(1, marked: 2, origin: 1) == .origin)
        #expect(M.frame(1, marked: 1, origin: 1) == .marked)
        #expect(M.frame(3, marked: 2, origin: 1) == .plain)
    }
}

@Suite("AppStripModel: keys")
struct AppStripKeyTests {
    private let ids = [10, 20, 30]
    private let pickable = [true, false, true]
    private func act(_ key: FilterKey) -> M.Action { M.action(for: key, ids: ids, pickable: pickable, marked: 10) }

    @Test("Enter chooses the marked window, Escape goes back")
    func enterEscape() {
        #expect(act(.enter) == .commit(10))
        #expect(act(.escape) == .cancel)
    }

    @Test("Tab and → step on, Shift-Tab and ← back")
    func steps() {
        #expect(act(.next) == .step(1) && act(.previous) == .step(-1))
    }

    @Test("⌘ and a digit goes straight to that window, as ⌘1–⌘9 pick a tab, even one a step would pass over; beyond the strip it is nothing")
    func commandDigits() {
        #expect(act(.commandDigit(2)) == .commit(20))
        #expect(act(.commandDigit(4)) == .none)
    }

    @Test("a plain digit or letter is nothing: the strip has no typing, and the keys are ⌘'s")
    func plainKeys() {
        #expect(act(.character("2")) == .none && act(.character("c")) == .none && act(.character("@")) == .none)
    }

    @Test("Home and End mark the first and the last window that can be picked")
    func homeEnd() {
        #expect(act(.home) == .select(10) && act(.end) == .select(30))
    }

    @Test("keys the strip has no use for are nothing: no typing, no rows")
    func others() {
        #expect(act(.backspace) == .none && act(.up) == .none && act(.down) == .none)
    }

    @Test("every window is labelled with its key, ⌘1–⌘9, and none past the ninth")
    func labels() {
        #expect(M.keyLabel(0) == "⌘1" && M.keyLabel(8) == "⌘9")
        #expect(M.keyLabel(9) == nil && M.keyLabel(-1) == nil)
    }

    @Test("the strip says how many windows, and on how many workspaces only when there is more than one")
    func summary() {
        #expect(M.summary(windows: 6, workspaces: 2) == "6 windows on 2 workspaces")
        #expect(M.summary(windows: 2, workspaces: 1) == "2 windows")
    }

    @Test("the marked window's title follows the app's name, unless it only repeats it")
    func markedTitle() {
        #expect(M.title("adv tui", appName: "Ghostty") == "adv tui")
        #expect(M.title("Ghostty", appName: "Ghostty") == nil)
        #expect(M.title("  ", appName: "Ghostty") == nil)
    }
}
