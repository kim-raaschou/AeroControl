import Foundation
import Testing
@testable import Common

// Type-to-filter, the pure half: which windows a query picks out, and what a keystroke does
// to the query. Everything AppKit and SwiftUI do with the answers is a thin shell over these.

private func window(_ id: Int, _ app: String, _ title: String = "") -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", title: title)
}

/// Two Teams windows (only the title tells them apart), a Code window, and an accented title.
private var model: OverviewModel { OverviewModel(workspaces: [
    WorkspaceInfo(name: "1", windows: [window(1, "Teams", "Crew standup"),
                                       window(2, "Teams", "Chat")]),
    WorkspaceInfo(name: "2", windows: [window(3, "Code", "AeroControl — main"),
                                       window(4, "Safari", "Café Münster")]),
]) }

private func ids(_ query: String) -> [Int] {
    model.matching(query).map(\.window.windowId)
}

@Suite("matching")
struct OverviewMatchingTests {

    @Test("an app name matches, in AeroSpace's own order")
    func matchesAppName() {
        #expect(ids("Teams") == [1, 2])
        #expect(ids("e") == [1, 3, 4, 2])      // every name or title holds an "e"; titles first
    }

    @Test("a title matches, which is the point: two windows of the same app")
    func matchesTitle() {
        #expect(ids("standup") == [1])
    }

    @Test("a title match outranks an app-name match: the meeting you named, not the app's rest")
    func titlesRankAboveAppNames() {
        let teams = OverviewModel(workspaces: [
            WorkspaceInfo(name: "1", windows: [window(1, "Teams"), window(2, "Teams"),
                                               window(3, "Slack", "Teams migration"), window(4, "Teams")]),
        ])
        #expect(teams.matching("teams").map(\.window.windowId) == [3, 1, 2, 4])
    }

    @Test("the fold is the invariant one, never the host's locale")
    func foldingIgnoresLocale() {
        let mail = OverviewModel(workspaces: [
            WorkspaceInfo(name: "1", windows: [window(1, "Mail", "Inbox")]),
        ])
        #expect(mail.matching("i").map(\.window.windowId) == [1])
        // The same fold in a Turkish locale, where "I" is the dotless ı's capital: what a
        // localized predicate does on a Turkish Mac, and what no test in another locale sees.
        #expect("Inbox".range(of: "i", options: [.caseInsensitive, .diacriticInsensitive],
                              range: nil, locale: Locale(identifier: "tr_TR")) == nil)
    }

    @Test("case and diacritics are ignored, so the query can be typed flat")
    func ignoresCaseAndDiacritics() {
        #expect(ids("teAMs") == [1, 2])
        #expect(ids("cafe munster") == [4])
    }

    @Test("an empty or blank query matches nothing: the filter is off, not everything")
    func emptyMatchesNothing() {
        #expect(ids("").isEmpty)
        #expect(ids("   ").isEmpty)
    }

    @Test("a match carries the workspace it lives on")
    func carriesWorkspace() {
        #expect(model.matching("Café").first?.workspace == "2")
    }

    @Test("a query nothing holds matches nothing")
    func missMatchesNothing() {
        #expect(ids("zzz").isEmpty)
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

        let all = grid("a")                              // every window matches: the whole map
        #expect(all.map(\.0) == ["1", "2"])
        #expect(all.map(\.1) == [[1, 2], [3, 4]])
    }

    @Test("cards keep AeroSpace's order, whatever order the matches came back in")
    func keepsGridOrder() {
        // "e" ranks the title matches first (1, 3, 4, then 2); the grid is still 1 then 2.
        #expect(grid("e").map(\.1) == [[1, 2], [3, 4]])
    }

    @Test("no match is no grid: the caller draws the whole map rather than an empty screen")
    func missDrawsNothing() {
        #expect(grid("zzz").isEmpty)
        #expect(grid("").isEmpty)
    }
}

@Suite("filterOrdinals")
struct FilterOrdinalsTests {

    @Test("the first nine matches are numbered in match order — what ⌘1…⌘9 picks")
    func numbersTheFirstNine() {
        #expect(filterOrdinals(matches: model.matching("e")) == [1: 1, 3: 2, 4: 3, 2: 4])
        #expect(filterOrdinals(matches: model.matching("zzz")).isEmpty)
    }

    @Test("past the ninth there are no digits left, so those tiles are not numbered")
    func stopsAtNine() {
        let many = OverviewModel(workspaces: [
            WorkspaceInfo(name: "1", windows: (1...12).map { window($0, "Teams") }),
        ])
        let ordinals = filterOrdinals(matches: many.matching("Teams"))
        #expect(ordinals.count == 9)
        #expect(ordinals[9] == 9 && ordinals[10] == nil)
    }
}

@Suite("filterKeyAction")
struct FilterKeyActionTests {
    private var matches: [ParsedWindow] { model.matching("Teams") }

    private func action(_ query: String, _ key: FilterKey, matches: [ParsedWindow]? = nil) -> FilterKeyAction {
        filterKeyAction(query: query, matches: matches ?? self.matches, key: key)
    }

    @Test("a letter is appended to the query")
    func typingAppends() {
        #expect(action("Tea", .character("m")) == .setQuery("Team"))
        #expect(action("", .character("T")) == .setQuery("T"))
    }

    @Test("backspace shortens the query, and on an empty one is not ours")
    func backspace() {
        #expect(action("Team", .backspace) == .setQuery("Tea"))
        #expect(action("", .backspace) == .none)
    }

    @Test("escape clears the query, and on an empty one is not ours: the window dismisses")
    func escapeClearsThenIsNotOurs() {
        #expect(action("Team", .escape) == .setQuery(""))
        #expect(action("", .escape) == .none)
        // Exhaustive on purpose: there is no case here promising a dismissal that this
        // function's one caller only ever turns back into "not ours".
        switch action("", .escape) {
        case .none, .setQuery, .focus: break
        }
    }

    @Test("enter focuses only when the query has narrowed to exactly one window")
    func enterNeedsOneMatch() {
        #expect(action("Teams", .enter) == .none)
        #expect(action("standup", .enter, matches: model.matching("standup")) == .focus(windowId: 1))
        #expect(action("zzz", .enter, matches: []) == .none)
    }

    @Test("a digit 1-9 always picks and never types, whatever the query already holds")
    func digitsAlwaysPick() {
        let two = model.matching("Teams")
        #expect(two.count == 2)
        #expect(action("Teams", .character("2")) == .focus(windowId: two[1].window.windowId))
        // Out of range is inert, not text: the digit must mean one thing at all times, or
        // `Teams2` focuses a window instead of narrowing, silently and with no way back.
        #expect(action("Teams", .character("5")) == .none)
        #expect(action("", .character("1"), matches: []) == .none)
    }

    @Test("zero is text, because no tile is ever labelled zero")
    func zeroTypes() {
        #expect(action("ws", .character("0")) == .setQuery("ws0"))
    }

    @Test("a digit from another script is text: only the digits the tiles wear can pick")
    func nonASCIIDigitTypes() {
        #expect(action("x", .character("٣")) == .setQuery("x٣"))
    }

    @Test("a query cannot start with a space, but can hold one")
    func leadingSpaceRejected() {
        #expect(action("", .character(" ")) == .none)
        #expect(action("cafe", .character(" ")) == .setQuery("cafe "))
        #expect(ids("cafe munster") == [4])
    }
}

@Suite("FilterKey.typed")
struct FilterKeyTypedTests {

    @Test("text is a key")
    func textIsAKey() {
        #expect(FilterKey.typed("a") == .character("a"))
        #expect(FilterKey.typed("é") == .character("é"))
        #expect(FilterKey.typed(" ") == .character(" "))
    }

    @Test("arrow and function keys arrive as private-use scalars, and are not text")
    func rejectsPrivateUseScalars() {
        #expect(FilterKey.typed(Character(UnicodeScalar(0xF700)!)) == nil)   // up arrow
        #expect(FilterKey.typed(Character(UnicodeScalar(0xF704)!)) == nil)   // F1
    }

    @Test("control characters are not text either")
    func rejectsControlCharacters() {
        #expect(FilterKey.typed("\u{3}") == nil)
        #expect(FilterKey.typed("\t") == nil)
    }
}
