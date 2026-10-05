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

    @Test("a query picks the windows whose title, app name or workspace name has a word starting with each of its words", arguments: [
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
        ("code main", [3]),         // the words may come from different fields: app and title
        ("2 saf", [4]),             // and the workspace's name: Safari on workspace 2
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
        ("aerospace.toml", [2]),    // typed whole, punctuation and all: the same boundaries as the title's
        ("BECT-938", [3]),
        ("..", []),                 // punctuation alone is no word, and matches nothing
    ])
    func wordRules(query: String, expected: [Int]) {
        #expect(ids(query, in: words) == expected)
    }

    @Test("a match carries the workspace it lives on")
    func carriesWorkspace() {
        #expect(model.matching("Café").first?.workspace == "2")
    }

    @Test("matches come back in the order the grid draws them: workspace by workspace, so the first is the top-left one")
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
    /// The two Teams windows: what most rows resolve Enter against.
    private var two: [ParsedWindow] { model.matching("Teams") }

    private func action(_ query: String, _ key: FilterKey, ring: Int?? = nil) -> FilterKeyAction {
        filterKeyAction(query: query, ring: ring ?? two[0].window.windowId, key: key)
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
        ("code", .commandKey(2), .none),                 // ⌘2 is the strip's; the map leaves it be
        ("", .character(" "), .none),                    // a query cannot start with a space…
        ("cafe", .character(" "), .setQuery("cafe ")),   // …but can hold one
    ])
    func keys(query: String, key: FilterKey, expected: FilterKeyAction) {
        #expect(action(query, key) == expected)
    }

    /// Nothing walks the map: the ring is AeroSpace's focus, or the first match while typing,
    /// and Enter picks whichever it is on.
    @Test("Enter picks the window under the ring, and nothing when there is none; the map does not answer to the strip's keys")
    func picks() {
        #expect(action("Teams", .enter) == .focus(windowId: two[0].window.windowId))
        #expect(action("", .enter, ring: .some(7)) == .focus(windowId: 7))         // no query: AeroSpace's focused window
        #expect(action("zzz", .enter, ring: .some(nil)) == .none)                 // nothing focused, nothing matched
        for key in [FilterKey.next, .previous, .commandKey(1)] { #expect(action("Teams", key) == .none) }
    }
}

@Suite("FilterKey from a key code")
struct FilterKeyCodeTests {
    @Test("the keys the overview answers to, by macOS key code; Shift only matters to Tab", arguments: [
        (53, false, nil, .escape),
        (115, false, nil, nil),                          // Home and End are nobody's
        (51, false, nil, .backspace),
        (36, false, "\r", .enter),
        (76, false, nil, .enter),                        // keypad Enter
        (48, false, "\t", .next),
        (48, true, "\t", .previous),                     // Shift-Tab
        (124, false, nil, .next),                        // →
        (123, false, nil, .previous),                    // ←
        (0, false, "a", .character("a")),
        (0, true, "A", .character("A")),                 // Shift types capitals, it does not modify
        (126, false, "\u{F700}", nil),                   // ↑ — a private-use scalar, never text, and nobody's
        (122, false, "\u{F704}", nil),                   // F1 is nobody's
    ] as [(UInt16, Bool, String?, FilterKey?)])
    func code(keyCode: UInt16, shift: Bool, characters: String?, expected: FilterKey?) {
        #expect(FilterKey(keyCode: keyCode, shift: shift, characters: characters) == expected)
    }
}

@Suite("FilterKey(command:)")
struct FilterKeyCommandTests {
    @Test("⌘ with 1–9 or a–f is a window's key, the fifteen in order; ⌘ with anything else is somebody else's", arguments: [
        ("1", FilterKey?.some(.commandKey(1))),
        ("9", .commandKey(9)),
        ("a", .commandKey(10)),
        ("f", .commandKey(15)),
        ("0", nil),
        ("g", nil),
        ("q", nil),
        ("", nil),
        ("ab", nil),                       // a key that types two characters is not one key, and no crash
    ] as [(String, FilterKey?)])
    func command(characters: String, expected: FilterKey?) {
        #expect(FilterKey(command: characters) == expected)
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
