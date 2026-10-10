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
        #expect(M.stepIndex(0, count: 0, direction: 1) == nil)
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
    // Two strip cards side by side: 1, 2, 3 in a row, and 4, 5.
    private let card: (Int) -> Int? = { $0 < 4 ? 0 : 1 }
    private let cards: [GridWalk.Card] = [(CGRect(x: 0, y: 0, width: 300, height: 60), [1: .init(x: 0, y: 0, width: 90, height: 60), 2: .init(x: 100, y: 0, width: 90, height: 60), 3: .init(x: 200, y: 0, width: 90, height: 60)]),
                                          (CGRect(x: 320, y: 0, width: 200, height: 60), [4: .init(x: 320, y: 0, width: 90, height: 60), 5: .init(x: 420, y: 0, width: 90, height: 60)])]

    @Test("opened on the window after the one you are in, the centre with it")
    func opened() {
        let s = Strip.opened("com.app", origin: 2, ids: [1, 2, 3], recent: [])
        #expect(s == Strip(app: "com.app", marked: 3, centre: 3))
        #expect(Strip.opened("com.app", origin: nil, ids: [1, 2], recent: [2]).marked == 2)
    }

    @Test("a strip owns its app's windows; the map's marking owns them all")
    func owns() {
        let mail = WindowInfo(windowId: 1, appName: "Mail", bundleId: "mail"), teams = WindowInfo(windowId: 2, appName: "Teams", bundleId: "teams")
        #expect(Strip(app: "mail", marked: nil, centre: nil).owns(mail) && !Strip(app: "mail", marked: nil, centre: nil).owns(teams))
        #expect(Strip(app: nil, marked: 2, centre: nil).owns(mail) && Strip(app: nil, marked: 2, centre: nil).owns(teams))
    }

    @Test("the pointer marks: the marking moves, the centre stays")
    func marking() {
        let s = Strip(app: "a", marked: 1, centre: 1)
        #expect(s.marking(4) == Strip(app: "a", marked: 4, centre: 1))
    }

    @Test("← and → step round the ids, the centre with the marking; ⌘→ and ⌘← go to the next or previous workspace's first window, wrapping")
    func moved() {
        let s = Strip(app: "a", marked: 5, centre: 5), ids = [1, 2, 3, 4, 5]
        #expect(s.moved(.window(1), ids: ids, card: card, cards: cards) == Strip(app: "a", marked: 1, centre: 1))   // round the end
        #expect(s.moved(.window(1), ids: [], card: card, cards: cards) == s)                                             // nothing to step onto
        #expect(Strip(app: "a", marked: 2, centre: 2).moved(.workspace(1), ids: ids, card: card, cards: cards).marked == 4)
        #expect(s.moved(.workspace(1), ids: ids, card: card, cards: cards).marked == 1 && s.moved(.workspace(-1), ids: ids, card: card, cards: cards).marked == 1)
    }

    @Test("AeroSpace moved the focus: within the app the strip stands; anywhere else, another app or an empty workspace, the choice was made with AeroSpace and it is over")
    func following() {
        func w(_ id: Int, _ app: String) -> WindowInfo { WindowInfo(windowId: id, appName: app, bundleId: app) }
        let s = Strip(app: "a", marked: 1, centre: 1)
        #expect(s.following(w(5, "a")) == s)
        #expect(s.following(w(3, "b")) == nil)                                           // several windows or one: over
        #expect(s.following(nil) == nil)                                                 // an empty workspace
    }

    @Test("after the windows changed the marking stays on its window, the centre where it was; a closed one hands the marking, and the centre, to the one that took its place")
    func kept() {
        let s = Strip(app: "a", marked: 2, centre: 1)                  // pointed at 2, the keys left the centre on 1
        #expect(s.kept(before: [1, 2, 3], after: [1, 2, 3]) == s)                      // a title tick turns nothing under a still hand
        #expect(Strip(app: nil, marked: -2, centre: -2).kept(before: [1, 2], after: [1]) == Strip(app: nil, marked: -2, centre: -2))   // the map's, on an empty workspace: no window of its own to lose
        #expect(s.kept(before: [1, 2, 3], after: [3, 2, 1])?.marked == 2)
        #expect(s.kept(before: [1, 2, 3], after: [1, 3]) == Strip(app: "a", marked: 3, centre: 3))
        #expect(Strip(app: "a", marked: 3, centre: 3).kept(before: [1, 2, 3], after: [1, 2])?.marked == 2)   // the last closed: the one before
        #expect(s.kept(before: [1, 2, 3], after: []) == nil)                              // none left: the strip is over
    }
}

@Suite("AppStripModel: geometry")
struct AppStripGeometryTests {
    @Test("one card fills the view's width, up to most of the panel; more each take a 3.5th of it, up to a third of the panel")
    func cardHeight() {
        // A 1728 x 1085 screen (1.6), 24 of chrome round each card.
        func h(_ cards: Int, _ view: CGFloat = 1900) -> CGFloat { M.cardHeight(view: view, cards: cards, aspect: 1.6, chrome: 24, panelHeight: 1085) }
        #expect(h(1) == (1085 * M.tallest).rounded() && h(2) == (1085 * M.tallestOfSeveral).rounded() && h(5) == ((1900 / M.seen - 24) / 1.6).rounded(.down))
        #expect(h(5, 900) == ((900 / M.seen - 24) / 1.6).rounded(.down) && h(3, 900) == ((900 / 3 - 24) / 1.6).rounded(.down))   // three fit whole              // a narrow view: the neighbours cut by its edges
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

    @Test("the arrows, ⌘ and an arrow, and the app's key again move the marking; the model passes the move on")
    func moves() {
        for move in [StripMove.window(1), .window(-1), .row(-1), .row(1), .workspace(-1)] { #expect(act(.move(move)) == .move(move)) }
    }

    @Test("a workspace's name, the one on its card, goes to that workspace; 0 is 10; a name the strip has not, nothing")
    func workspaceNames() {
        func act(_ c: Character) -> M.Action { M.action(for: .character(c), ids: ids, marked: 10, workspaces: ["3", "4", "10"]) }
        #expect(act("4") == .move(.card(1)) && act("0") == .move(.card(2)) && act("7") == .none && act("a") == .none)
        #expect(Strip(app: "a", marked: 1, centre: 1).moved(.card(1), ids: [1, 2, 4, 5], card: { $0 < 4 ? 0 : 1 }) == Strip(app: "a", marked: 4, centre: 4))   // card 1's first
        #expect(Strip(app: "a", marked: 1, centre: 1).moved(.workspace(1), ids: [1, 9], card: { $0 < 4 ? 0 : 3 }).marked == 9)   // past the empty ones
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

    /// The lane under the strip is one line, as high as the map's: the app, how many windows,
    /// and the marked window's title, which is what Enter picks. Its key is on its card.
    @Test("the strip's line says how many windows, on how many workspaces when more than one, and the marked window's title, its workspace with several")
    func summary() {
        func w(_ id: Int, _ title: String, _ ws: String) -> ParsedWindow {
            ParsedWindow(window: WindowInfo(windowId: id, appName: "Ghostty", bundleId: "g", title: title), workspace: ws)
        }
        #expect(M.summary([w(1, "btop", "1"), w(2, "~/sources/advisor", "1")], marked: 2) == "2 windows · ~/sources/advisor")
        #expect(M.summary([w(1, "btop", "1"), w(2, "", "1")], marked: 2) == "2 windows · Ghostty")          // untitled: the app
        #expect(M.summary([w(1, "btop", "1"), w(3, "adv — Ghostty", "4")], marked: 3) == "2 windows on 2 workspaces · adv · ws 4")
        #expect(M.summary([w(1, "btop", "1"), w(2, "b", "1")], marked: nil) == "2 windows")
    }
}
