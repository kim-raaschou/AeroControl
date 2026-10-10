import Foundation

private extension String {
    /// Runs of letters and digits: what a title and a query are both cut into, so a query typed
    /// whole, "aerospace.toml" or "BECT-938", has the same boundaries as the title it names.
    var words: [Substring] { split(whereSeparator: { !$0.isLetter && !$0.isNumber }) }

    /// True when every word of the query begins some word here, case- and diacritic-insensitively.
    ///
    /// Word-anchored rather than anywhere in the string: a mid-word hit is the surprising
    /// kind, and the collapse is only trustworthy if you can see why each survivor survived.
    /// Anchored to the *word* and not the string because "Microsoft Teams" does not start
    /// with "teams", and that is the case the filter exists for. A word is a run of letters
    /// and digits, so `.` and `-` split: "toml" finds aerospace.toml and "938" finds BECT-938.
    ///
    /// The locale is named explicitly. The locale-aware fold is a trap: in a Turkish one "I"
    /// folds to "ı", so "Inbox" stops matching "i" — and a test in the host's locale would
    /// never see it.
    func hasWordsStarting(with needles: [Substring]) -> Bool {
        let words = self.words
        // Every typed word must start some word here, in any order — so "cafe mun" finds
        // "Café Münster" and "lars teams" finds a chat window whichever way round you type it.
        return needles.allSatisfy { needle in
            words.contains { word in
                word.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored],
                           range: nil, locale: nil) != nil
            }
        }
    }
}

public extension OverviewModel {
    /// Below this the query has not said anything yet, and collapsing the whole map on one
    /// keystroke is violent for no gain.
    static var minQueryLength: Int { 2 }

    /// Windows with a word starting with each word of `query` in their title, app name or
    /// workspace name together, each with the
    /// workspace it lives on, in the order the grid draws them: workspace by workspace,
    /// AeroSpace's own order inside each; the first is what Enter picks. A query shorter than
    /// `minQueryLength` matches nothing: the filter is not on yet, which is not the same as
    /// matching everything.
    func matching(_ query: String) -> [ParsedWindow] {
        let needles = query.words
        guard query.trimmingCharacters(in: .whitespaces).count >= Self.minQueryLength, !needles.isEmpty else { return [] }
        // Title, app and workspace read as one: "code main" is Code's window "main", "2 saf" Safari on 2.
        return windowsInGridOrder.filter { "\($0.window.title) \($0.window.appName) \($0.workspace)".hasWordsStarting(with: needles) }
    }

    /// Every window with its workspace, in the order the grid draws them.
    var windowsInGridOrder: [ParsedWindow] {
        workspaces.flatMap { workspace in workspace.windows.map { ParsedWindow(window: $0, workspace: workspace.name) } }
    }

    /// The windows a marking is of (`Strip.owns`), in the order the grid draws them: every one for
    /// the map's, or none yet.
    func windows(of marking: Strip?) -> [ParsedWindow] {
        windowsInGridOrder.filter { marking?.owns($0.window) ?? true }
    }

    /// The focused window, nil when nothing is focused.
    var focusedWindow: WindowInfo? {
        workspaces.lazy.flatMap(\.windows).first { $0.windowId == focusedWindowId }
    }

    /// The grid a query draws: every workspace holding one of `matches`, carrying only those
    /// windows, in AeroSpace's order. Empty when nothing matched, where the caller draws the
    /// full grid instead — the screen must never go dark with no way to read out of it.
    func workspaces(holding matches: [ParsedWindow]) -> [WorkspaceInfo] {
        let ids = Set(matches.map(\.window.windowId))
        guard !ids.isEmpty else { return [] }
        return workspaces.compactMap { workspace in
            let kept = workspace.windows.filter { ids.contains($0.windowId) }
            return kept.isEmpty ? nil : workspace.with(windows: kept)
        }
    }
}

/// A keystroke the overview understands, named by what it means rather than by its key code:
/// the mapping from an `NSEvent` is AppKit's job, and `Common` never sees one.
public enum FilterKey: Equatable, Sendable {
    case character(Character)
    case backspace
    case enter
    case escape
    /// A marking moved, the strip's or the map's: ← and → a window, through a workspace's and
    /// on to the next; ↑ and ↓ a row; ⌘ and an arrow a workspace along, above or below.
    case move(StripMove)
    /// ⌘1–⌘9, ⌘a–⌘f: the strip's window with that key, 1 to 15; nothing on the map.
    case commandKey(Int)
    /// ⇧⌘ and a workspace's name: the window under the ring goes there, on the map and in the strip.
    case moveToWorkspace(String)
}

public extension FilterKey {
    /// The key a keyboard event stands for, from the parts of it that matter; nil when it is
    /// not one of ours. The caller has already ruled out Cmd, Ctrl and Option. Shift is not
    /// a modifier here: it is how capitals are typed.
    init?(keyCode: UInt16, characters: String?) {
        switch keyCode {
        case 53: self = .escape
        case 51: self = .backspace
        case 36, 76: self = .enter
        case 124: self = .move(.window(1))
        case 123: self = .move(.window(-1))
        case 126: self = .move(.row(-1))
        case 125: self = .move(.row(1))
        default:
            guard let key = characters?.first.flatMap(FilterKey.typed) else { return nil }
            self = key
        }
    }

    /// The keys the strip's windows carry, in order: ⌘1–⌘9 as macOS numbers tabs, then ⌘a–⌘f, fifteen in all.
    public static let windowKeys: [Character] = Array("123456789abcdef")

    /// The workspace a key names: its own character, 0 the tenth, as the keys count; nil for a key
    /// that types no text (an arrow), or more than one character.
    public static func workspaceNamed(_ key: String) -> String? {
        guard key.count == 1, let c = key.first, typed(c) != nil else { return nil }
        return ["0": "10"][key] ?? key
    }

    /// ⌘ with 1–9 or a–f is a window's key, the fifteen in that order, ⌘ with an arrow a
    /// workspace along or the one above or below; ⌘ with anything else is somebody else's (⌘Q, ⌘W).
    private static let commandKeys: [String: FilterKey] = Dictionary(uniqueKeysWithValues: windowKeys.enumerated().map { (String($1), .commandKey($0 + 1)) })
        .merging(["\u{F703}": .move(.workspace(1)), "\u{F702}": .move(.workspace(-1)), "\u{F700}": .move(.workspaceRow(-1)), "\u{F701}": .move(.workspaceRow(1))]) { a, _ in a }

    init?(command characters: String, shift: Bool) {
        guard let key = shift ? Self.workspaceNamed(characters).map(FilterKey.moveToWorkspace) : Self.commandKeys[characters] else { return nil }
        self = key
    }

    /// The key a typed character stands for, or nil when it is not text. Arrow and function
    /// keys arrive as private-use scalars (0xF700+), not control characters — reject both.
    static func typed(_ character: Character) -> FilterKey? {
        guard let scalar = character.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              scalar.value < 0xF700 else { return nil }
        return .character(character)
    }
}

public enum FilterKeyAction: Equatable, Sendable {
    /// Not ours: the window handles the key as it did before there was a filter.
    case none
    case setQuery(String)
    case focus(windowId: Int)
    /// Taken, and nothing for the caller to do: a step in the strip, or a key it swallows.
    case handled
}

/// What a keystroke does to the filter. Nothing walks the map: `ring` is the window wearing
/// the ring — AeroSpace's focus, or the first match while a query stands — and Enter picks
/// it. A match is picked by typing until it is first. Everything typed is text, digits
/// included — "code2" narrows the query and nothing else; there is nothing on screen to read
/// a key off.
public func filterKeyAction(query: String, ring: Int?, key: FilterKey) -> FilterKeyAction {
    switch key {
    case .escape:
        return query.isEmpty ? .none : .setQuery("")
    case .enter:
        return ring.map { .focus(windowId: $0) } ?? .none
    case .move, .commandKey, .moveToWorkspace:
        return .none
    case .backspace:
        return query.isEmpty ? .none : .setQuery(String(query.dropLast()))
    case .character(let character):
        // A query is trimmed before it is matched, so one starting with a space shows a pill
        // with nothing in it over an unchanged grid, and the next Escape spends itself
        // clearing it. Internal spaces are text like any other ("cafe munster").
        guard !(query.isEmpty && character.isWhitespace) else { return .none }
        return .setQuery(query + String(character))
    }
}
