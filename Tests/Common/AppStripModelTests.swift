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

    @Test("from outside the app the marking opens on the app's window you used last, as ⌘Tab goes back to it; known none, on the first")
    func startOnLastUsed() {
        #expect(M.start(origin: nil, ids: [1, 2, 3], recent: [9, 3, 1]) == 3)          // 9 is another app's
        #expect(M.start(origin: nil, ids: [1, 2, 3], recent: [8, 9]) == 1)
        #expect(M.start(origin: 2, ids: [1, 2, 3], recent: [1]) == 3)                  // inside the app: the next, as before
    }

    @Test("the marked window keeps the marking when others move; a closed one hands it to its successor")
    func keepSelection() {
        #expect(M.keepSelection(3, lastIndex: 0, ids: [1, 2, 3]) == 3)
        #expect(M.keepSelection(9, lastIndex: 1, ids: [1, 3]) == 3)
        #expect(M.keepSelection(9, lastIndex: 5, ids: [1, 3]) == 3)
        #expect(M.keepSelection(1, lastIndex: 0, ids: []) == nil)
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

}

@Suite("AppStripModel: keys")
struct AppStripKeyTests {
    private let ids = [10, 20, 30]
    private func act(_ key: FilterKey) -> M.Action { M.action(for: key, ids: ids, marked: 10) }

    @Test("Enter chooses the marked window, Escape goes back")
    func enterEscape() {
        #expect(act(.enter) == .commit(10))
        #expect(act(.escape) == .cancel)
    }

    @Test("Tab and → step on, Shift-Tab and ← back")
    func steps() {
        #expect(act(.next) == .step(1) && act(.previous) == .step(-1))
    }

    @Test("⌘ and a digit goes straight to that window, as ⌘1–⌘9 pick a tab; beyond the strip it is nothing")
    func commandDigits() {
        #expect(act(.commandDigit(2)) == .commit(20))
        #expect(act(.commandDigit(4)) == .none)
    }

    @Test("a plain digit or letter is nothing: the strip has no typing, and the keys are ⌘'s")
    func plainKeys() {
        #expect(act(.character("2")) == .none && act(.character("c")) == .none && act(.character("@")) == .none)
    }

    @Test("Home and End mark the first and the last window")
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
