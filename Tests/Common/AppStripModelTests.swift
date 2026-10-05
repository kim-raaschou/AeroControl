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

    @Test("knowing nothing used before, the marking opens on the window after the one you are in; with two, on the other; from outside the app, on the first")
    func start() {
        #expect(M.start(origin: 2, ids: [1, 2, 3]) == 3)
        #expect(M.start(origin: 3, ids: [1, 2, 3]) == 1)
        #expect(M.start(origin: 1, ids: [1, 2]) == 2 && M.start(origin: 2, ids: [1, 2]) == 1)
        #expect(M.start(origin: 9, ids: [1, 2, 3]) == 1 && M.start(origin: nil, ids: [1, 2]) == 1)
        #expect(M.start(origin: 1, ids: []) == nil)
    }

    @Test("the marking opens on the app's window you used last before the one you are in, as ⌘` and ⌘Tab go back to it; known none, as above")
    func startOnLastUsed() {
        #expect(M.start(origin: nil, ids: [1, 2, 3], recent: [9, 3, 1]) == 3)          // from outside; 9 is another app's
        #expect(M.start(origin: nil, ids: [1, 2, 3], recent: [8, 9]) == 1)
        #expect(M.start(origin: 2, ids: [1, 2, 3], recent: [1]) == 1)                  // inside the app: back to the one before
        #expect(M.start(origin: 2, ids: [1, 2, 3], recent: [2, 3, 1]) == 3)            // the one you are in is not the one before it
        #expect(M.start(origin: 2, ids: [1, 2, 3], recent: [2]) == 3)                  // nothing before it: the next
    }
}

/// The strip as a value: every change is a new strip, so nothing is ever half-updated and a
/// change is one assignment. The store only holds the current one.
@Suite("Strip: a value that steps")
struct StripValueTests {
    private let cards: (Int) -> Int? = { [1, 2, 3].contains($0) ? 0 : [4, 5].contains($0) ? 1 : nil }

    @Test("opened on the window after the one you are in, the centre with it, no turns yet")
    func opened() {
        let s = Strip.opened("com.app", origin: 2, ids: [1, 2, 3], recent: [])
        #expect(s == Strip(bundleId: "com.app", marked: 3, centre: 3, turns: 0))
        #expect(Strip.opened("com.app", origin: nil, ids: [1, 2], recent: [2]).marked == 2)
    }

    @Test("the pointer marks: the marking moves, the centre stays")
    func marking() {
        let s = Strip(bundleId: "a", marked: 1, centre: 1, turns: 0)
        #expect(s.marking(4) == Strip(bundleId: "a", marked: 4, centre: 1, turns: 0))
    }

    @Test("stepping wraps round the ids and counts a turn when it passes the last card forward, or the first backward")
    func stepped() {
        let s = Strip(bundleId: "a", marked: 5, centre: 5, turns: 0)
        let on = s.stepped(1, ids: [1, 2, 3, 4, 5], card: cards)
        #expect(on.marked == 1 && on.centre == 1 && on.turns == 1)            // 5 (card 1) → 1 (card 0): round the end
        let back = on.stepped(-1, ids: [1, 2, 3, 4, 5], card: cards)
        #expect(back.marked == 5 && back.turns == 0)                          // and back again
        #expect(s.stepped(1, ids: [], card: cards).marked == 5)               // nothing to step onto: unchanged
    }

    @Test("AeroSpace moved the focus: within the app nothing changes; to another app of several windows the strip turns to it, marked there; to an app of one window it is over")
    func following() {
        func w(_ id: Int, _ app: String) -> WindowInfo { WindowInfo(windowId: id, appName: app, bundleId: app) }
        let windows = [w(1, "a"), w(2, "b"), w(3, "b"), w(4, "c")]
        let s = Strip(bundleId: "a", marked: 1, centre: 1, turns: 2)
        #expect(s.following(w(1, "a"), among: windows) == s)
        #expect(s.following(nil, among: windows) == s)                                   // an empty workspace
        #expect(s.following(w(3, "b"), among: windows) == Strip(bundleId: "b", marked: 3, centre: 3, turns: 0))
        #expect(s.following(w(4, "c"), among: windows) == nil)                          // nothing to choose there
    }

    @Test("after the windows changed the marking stays on its window, the centre where it was; a closed one hands the marking, and the centre, to the one that took its place")
    func kept() {
        let s = Strip(bundleId: "a", marked: 2, centre: 1, turns: 0)                  // pointed at 2, the keys left the centre on 1
        #expect(s.kept(before: [1, 2, 3], after: [1, 2, 3]) == s)                      // a title tick turns nothing under a still hand
        #expect(s.kept(before: [1, 2, 3], after: [3, 2, 1])?.marked == 2)
        #expect(s.kept(before: [1, 2, 3], after: [1, 3]) == Strip(bundleId: "a", marked: 3, centre: 3, turns: 0))
        #expect(Strip(bundleId: "a", marked: 3, centre: 3, turns: 0).kept(before: [1, 2, 3], after: [1, 2])?.marked == 2)   // the last closed: the one before
        #expect(s.kept(before: [1, 2, 3], after: []) == nil)                              // none left: the strip is over
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

    @Test("⌘ and a window's key goes straight to that window, as ⌘1–⌘9 pick a tab; beyond the strip it is nothing")
    func commandKeys() {
        #expect(act(.commandKey(2)) == .commit(20))
        #expect(act(.commandKey(4)) == .none)
        let fifteen = Array(1...15), sixteen = Array(1...16)
        #expect(M.action(for: .commandKey(10), ids: fifteen, marked: nil) == .commit(10))     // ⌘a
        #expect(M.action(for: .commandKey(15), ids: sixteen, marked: nil) == .commit(15))     // ⌘f, the last key
        #expect(M.action(for: .commandKey(16), ids: sixteen, marked: nil) == .none)           // the sixteenth has no key
    }

    @Test("a plain digit or letter is nothing: the strip has no typing, and the keys are ⌘'s")
    func plainKeys() {
        #expect(act(.character("2")) == .none && act(.character("c")) == .none && act(.character("@")) == .none)
    }

    @Test("keys the strip has no use for are nothing: no typing, no rows")
    func others() {
        #expect(act(.backspace) == .none && act(.character("x")) == .none)
    }

    @Test("every window is labelled with its key, ⌘1–⌘9 then ⌘a–⌘f, and none past the fifteenth")
    func labels() {
        #expect(M.keyLabel(0) == "⌘1" && M.keyLabel(8) == "⌘9")
        #expect(M.keyLabel(9) == "⌘a" && M.keyLabel(14) == "⌘f")
        #expect(M.keyLabel(15) == nil && M.keyLabel(-1) == nil)
    }

    @Test("the strip says how many windows, and on how many workspaces only when there is more than one")
    func summary() {
        #expect(M.summary(windows: 6, workspaces: 2) == "6 windows on 2 workspaces")
        #expect(M.summary(windows: 2, workspaces: 1) == "2 windows")
    }

    /// The legend is where a window is told apart when its picture cannot be: a key, its
    /// caption, and its workspace when the app spans more than one. The cards stay true to
    /// AeroSpace; the legend is readable whatever AeroSpace did to the geometry.
    @Test("the legend names every window of the app: key, caption, the workspace only when there are several, the marked one marked")
    func legend() {
        func w(_ id: Int, _ title: String, _ ws: String) -> ParsedWindow {
            ParsedWindow(window: WindowInfo(windowId: id, appName: "Ghostty", bundleId: "g", title: title), workspace: ws)
        }
        let rows = M.legend([w(1, "btop", "1"), w(2, "", "1"), w(3, "adv — Ghostty", "4")], marked: 2)
        #expect(rows.map(\.key) == ["⌘1", "⌘2", "⌘3"])
        #expect(rows.map(\.title) == ["btop", "Ghostty", "adv"])               // untitled: the app; the app's name pushed out
        #expect(rows.map(\.workspace) == ["1", "1", "4"])
        #expect(rows.map(\.marked) == [false, true, false])
        let one = M.legend([w(1, "a", "1"), w(2, "b", "1")], marked: nil)
        #expect(one.map(\.workspace) == [nil, nil] && !one.contains { $0.marked })   // one workspace: not said
        let many = M.legend((1...11).map { w($0, "t\($0)", "1") }, marked: 11)
        #expect(many[8].key == "⌘9" && many[9].key == "⌘a" && many[10].marked)       // the tenth is ⌘a; every window is a row
    }
}
