import Foundation
import Testing
@testable import Common

// Type-to-filter, the pure half: which windows a query picks out, and what a keystroke does
// to the query. Everything AppKit and SwiftUI do with the answers is a thin shell over these.

private func window(_ id: Int, _ app: String, _ title: String = "") -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", title: title)
}

/// Two Teams windows (only the title tells them apart), a Code window, and an accented title.
/// Anything that asserts an *order* runs against this one.
private var model: OverviewModel { OverviewModel(workspaces: [
    WorkspaceInfo(name: "1", windows: [window(1, "Teams", "Crew standup"),
                                       window(2, "Teams", "Chat")]),
    WorkspaceInfo(name: "2", windows: [window(3, "Code", "AeroControl — main"),
                                       window(4, "Safari", "Café Münster")]),
]) }

/// Awkward strings for the word rules. Only ever asserted for membership, so adding a row
/// here cannot disturb the ordered tests above.
private var words: OverviewModel { OverviewModel(workspaces: [
    WorkspaceInfo(name: "1", windows: [window(1, "Microsoft Teams", "Chat | Lars | Microsoft Teams"),
                                       window(2, "Code", "aerospace.toml — .config"),
                                       window(3, "Arc", "BECT-938: the tenant check"),
                                       window(4, "Mail", "Inbox")]),
]) }

private func ids(_ query: String, in model: OverviewModel = model) -> [Int] {
    model.matching(query).map(\.window.windowId)
}

@Suite("matching")
struct OverviewMatchingTests {

    @Test("a query picks the windows whose title or app name has a word starting with it", arguments: [
        ("Teams", [1, 2]),          // app name, in AeroSpace's order
        ("saf", [4]),               // app name, not the title
        ("standup", [1]),           // title: the point — two windows of one app told apart
        ("te", [1, 2]),             // two letters is a query
        ("teAMs", [1, 2]),          // case is ignored
        ("cafe munster", [4]),      // diacritics too, and a query with a space matches word by word
        ("eams", []),               // inside "Teams": a mid-word hit is the surprising kind
        ("tandup", []),             // inside "standup"
        ("t", []),                  // one letter is not a query yet: the map stays standing
        ("", []),                   // the filter is off, not "everything"
        ("   ", []),
        ("zzz", []),                // a real miss
    ])
    func matches(query: String, expected: [Int]) {
        #expect(ids(query) == expected)
    }

    @Test("a word anywhere can start the match, and punctuation is a word boundary", arguments: [
        ("teams", [1]),             // second word of the app name
        ("lars", [1]),              // between pipes
        ("toml", [2]),              // after a dot
        ("938", [3]),               // after a hyphen: a digit reached through the filter
        ("in", [4]),                // the fold is locale-invariant: "Inbox" must match "in" everywhere
        ("space", []),              // mid-word in "aerospace"
    ])
    func wordRules(query: String, expected: [Int]) {
        #expect(ids(query, in: words) == expected)
    }

    @Test("a match carries the workspace it lives on")
    func carriesWorkspace() {
        #expect(model.matching("Café").first?.workspace == "2")
    }

    @Test("matches come back in the order the grid draws them: workspace by workspace, so Tab walks across")
    func orderIsPlacement() {
        // A title match on workspace 2 must not jump ahead of the app-name matches on workspace 1.
        let spread = OverviewModel(workspaces: [
            WorkspaceInfo(name: "1", windows: [window(1, "Teams"), window(2, "Teams")]),
            WorkspaceInfo(name: "2", windows: [window(3, "Slack", "Teams migration"), window(4, "Teams")]),
        ])
        let matches = spread.matching("teams")
        #expect(matches.map(\.window.windowId) == [1, 2, 3, 4])
        #expect(spread.workspaces(holding: matches).map { $0.windows.map(\.windowId) } == [[1, 2], [3, 4]])
    }
}

@Suite("focusedAppName")
struct FocusedAppNameTests {
    @Test("the focused window's app, or nil when nothing is focused; typed, it lists that app's windows")
    func focusedApp() {
        var focused = model
        focused.focusedWindowId = 2
        #expect(focused.focusedAppName == "Teams")
        #expect(ids(focused.focusedAppName!, in: focused) == [1, 2])
        focused.focusedWindowId = 99
        #expect(focused.focusedAppName == nil)
    }
}

@Suite("the filtered grid")
struct FilteredWorkspacesTests {
    private func grid(_ query: String) -> [(String, [Int])] {
        model.workspaces(holding: model.matching(query))
            .map { ($0.name, $0.windows.map(\.windowId)) }
    }

    @Test("a workspace with no match is gone, and the rest keep only their matches")
    func dropsAndTrims() {
        let teams = grid("Teams")
        #expect(teams.map(\.0) == ["1"])                 // workspace 2 holds no Teams window
        #expect(teams.map(\.1) == [[1, 2]])
    }

    @Test("no match is no grid: the caller draws the whole map rather than an empty screen", arguments: [
        "zzz", "", "c",                                  // a miss, the filter off, below the threshold
    ])
    func missDrawsNothing(query: String) {
        #expect(grid(query).isEmpty)
    }
}

@Suite("filterKeyAction")
struct FilterKeyActionTests {
    /// The two Teams windows: what most rows resolve Enter and Tab against.
    private var two: [ParsedWindow] { model.matching("Teams") }

    private func action(_ query: String, _ key: FilterKey, matches: [ParsedWindow]? = nil, selection: Int = 0) -> FilterKeyAction {
        filterKeyAction(query: query, matches: matches ?? two, selection: selection, key: key)
    }

    /// Six Teams windows on workspace 1 (drawn 3 wide) and two on workspace 2 (2 wide).
    private var eight: [ParsedWindow] {
        OverviewModel(workspaces: [
            WorkspaceInfo(name: "1", windows: (1...6).map { window($0, "Teams") }),
            WorkspaceInfo(name: "2", windows: (7...8).map { window($0, "Teams") }),
        ]).matching("Teams")
    }

    @Test("what a keystroke does to the query, against two matches", arguments: [
        ("Tea", FilterKey.character("m"), FilterKeyAction.setQuery("Team")),
        ("", .character("T"), .setQuery("T")),
        ("Team", .backspace, .setQuery("Tea")),
        ("", .backspace, .none),                         // not ours
        ("Team", .escape, .setQuery("")),                // clear first…
        ("", .escape, .none),                            // …then the window dismisses
        ("code", .character("2"), .setQuery("code2")),   // a digit is text: nothing on screen answers to a key
        ("x", .character("٣"), .setQuery("x٣")),
        ("", .character(" "), .none),                    // a query cannot start with a space…
        ("cafe", .character(" "), .setQuery("cafe ")),   // …but can hold one
    ])
    func keys(query: String, key: FilterKey, expected: FilterKeyAction) {
        #expect(action(query, key) == expected)
    }

    @Test("Enter picks the match the ring is on — the first until Tab says otherwise")
    func picks() {
        #expect(action("Teams", .enter) == .focus(windowId: two[0].window.windowId))
        #expect(action("Teams", .enter, selection: 1) == .focus(windowId: two[1].window.windowId))
        #expect(action("standup", .enter, matches: model.matching("standup")) == .focus(windowId: 1))
        #expect(action("zzz", .enter, matches: []) == .none)               // a miss: nothing to stand on
        // The list shrank under the index (a window closed mid-query): the ring clamps to the
        // last match, and Enter picks that same one rather than nothing.
        #expect(action("Teams", .enter, selection: 5) == .focus(windowId: two[1].window.windowId))
        #expect(two.selected(5)?.window.windowId == two[1].window.windowId)
    }

    @Test("↑/↓ move a tile row: same column, next row; off the card, the same column on the next card", arguments: [
        (0, true, 3),        // ws 1 is 3 wide: down from the first is the one below it
        (3, true, 6),        // last row of ws 1, column 0: down lands on ws 2's first
        (5, true, 7),        // column 2, but ws 2 is 2 wide: clamped to its last column
        (6, true, 0),        // off the last card: round to the first
        (4, false, 1),       // up within the card
        (7, false, 4),       // up out of ws 2, column 1: ws 1's last row, column 1
        (0, false, 6),       // up off the first card: the last card's last row
    ])
    func rows(from: Int, down: Bool, expected: Int) {
        #expect(eight.neighbor(of: from, columns: ["1": 3, "2": 2], cardRows: [["1", "2"]], down: down) == expected)
    }

    @Test("across rows of cards: ↓ leaves for the card below, nearest column, skipping cards with nothing in them")
    func acrossCardRows() {
        // Cards drawn   1 2      ws 1: two windows (2 wide)   ws 2: one window
        //               3 4      ws 3: empty                  ws 4: two windows (2 wide)
        let map = OverviewModel(workspaces: [
            WorkspaceInfo(name: "1", windows: [window(1, "A"), window(2, "B")]),
            WorkspaceInfo(name: "2", windows: [window(3, "C")]),
            WorkspaceInfo(name: "3", windows: []),
            WorkspaceInfo(name: "4", windows: [window(4, "D"), window(5, "E")]),
        ]).windowsInGridOrder
        let rows = [["1", "2"], ["3", "4"]]
        let columns = ["1": 2, "2": 1, "4": 2]
        #expect(map.neighbor(of: 0, columns: columns, cardRows: rows, down: true) == 3)     // ws 1 → below is empty ws 3, so ws 4, column 0
        #expect(map.neighbor(of: 1, columns: columns, cardRows: rows, down: true) == 4)     // column 1 of ws 1 → column 1 of ws 4
        #expect(map.neighbor(of: 2, columns: columns, cardRows: rows, down: true) == 3)     // ws 2 → ws 4 right below
        #expect(map.neighbor(of: 3, columns: columns, cardRows: rows, down: false) == 2)    // ws 4 (card column 1) ↑ → ws 2, right above it
        #expect(map.neighbor(of: 2, columns: columns, cardRows: rows, down: false) == 3)    // ws 2 ↑ wraps to the row below: ws 4
    }

    @Test("a card nobody reported is one column wide and all cards one row; one window has nowhere to go")
    func rowsDefaults() {
        #expect(two.neighbor(of: 0, columns: [:], cardRows: [], down: true) == 1)
        #expect(two.neighbor(of: 1, columns: [:], cardRows: [], down: true) == 0)           // wraps within the only card
        #expect(eight.neighbor(of: 3, columns: ["1": 3], cardRows: [], down: true) == 6)    // unreported rows: the next card along
        #expect(model.matching("standup").neighbor(of: 0, columns: [:], cardRows: [], down: true) == nil)
        #expect(action("Teams", .down) == .select(1))
        #expect(action("zzz", .up, matches: []) == .none)
    }

    @Test("Tab and the arrows walk the matches and wrap at both ends")
    func walks() {
        #expect(action("Teams", .next) == .select(1))
        #expect(action("Teams", .next, selection: 1) == .select(0))
        #expect(action("Teams", .previous) == .select(1))
        #expect(action("Teams", .next, selection: 5) == .select(0))                          // walks on from the clamp
        #expect(action("standup", .next, matches: model.matching("standup")) == .none)   // one match: nowhere to go
        #expect(action("zzz", .previous, matches: []) == .none)
    }

    @Test("the action vocabulary is exactly these four")
    func exhaustive() {
        // A compile-time guard: there is no case here promising a dismissal that this
        // function's one caller only ever turns back into "not ours".
        switch action("", .escape) {
        case .none, .setQuery, .select, .focus: break
        }
    }
}

@Suite("FilterKey from a key code")
struct FilterKeyCodeTests {
    @Test("the keys the overview answers to, by macOS key code; Shift only matters to Tab", arguments: [
        (53, false, nil, .escape),
        (51, false, nil, .backspace),
        (36, false, "\r", .enter),
        (76, false, nil, .enter),                        // keypad Enter
        (48, false, "\t", .next),
        (48, true, "\t", .previous),                     // Shift-Tab
        (124, false, nil, .next),                        // →
        (123, false, nil, .previous),                    // ←
        (0, false, "a", .character("a")),
        (0, true, "A", .character("A")),                 // Shift types capitals, it does not modify
        (126, false, "\u{F700}", .up),                   // ↑ — a private-use scalar, never text
        (125, false, "\u{F701}", .down),
        (122, false, "\u{F704}", nil),                   // F1 is nobody's
    ] as [(UInt16, Bool, String?, FilterKey?)])
    func code(keyCode: UInt16, shift: Bool, characters: String?, expected: FilterKey?) {
        #expect(FilterKey(keyCode: keyCode, shift: shift, characters: characters) == expected)
    }
}

@Suite("FilterKey.typed")
struct FilterKeyTypedTests {

    @Test("text is a key; arrows, function keys and control characters are not", arguments: [
        ("a" as Character, FilterKey.character("a")),
        ("é", .character("é")),
        (" ", .character(" ")),
        (Character(UnicodeScalar(0xF700)!), nil),        // up arrow: a private-use scalar, not a glyph
        (Character(UnicodeScalar(0xF704)!), nil),        // F1
        ("\u{3}", nil),
        ("\t", nil),
    ])
    func typed(character: Character, expected: FilterKey?) {
        #expect(FilterKey.typed(character) == expected)
    }
}
