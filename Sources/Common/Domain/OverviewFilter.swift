import Foundation

private extension String {
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
        let words = split(whereSeparator: { !$0.isLetter && !$0.isNumber })
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

    /// Windows with a word starting with `query` in their title or app name, each with the
    /// workspace it lives on, in the order the grid draws them: workspace by workspace,
    /// AeroSpace's own order inside each. That order *is* the numbering — the keycaps read
    /// 1, 2, 3 across the screen because this list and the grid are the same list. A query
    /// shorter than `minQueryLength` matches nothing: the filter is not on yet, which is not
    /// the same as matching everything.
    func matching(_ query: String) -> [ParsedWindow] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= Self.minQueryLength else { return [] }
        let needles = needle.split(separator: " ")
        return workspaces.flatMap { workspace in
            workspace.windows
                .filter { $0.title.hasWordsStarting(with: needles) || $0.appName.hasWordsStarting(with: needles) }
                .map { ParsedWindow(window: $0, workspace: workspace.name) }
        }
    }

    /// The grid a query draws: every workspace holding one of `matches`, carrying only those
    /// windows, in AeroSpace's order. Empty when nothing matched, where the caller draws the
    /// full grid instead — the screen must never go dark with no way to read out of it.
    func workspaces(holding matches: [ParsedWindow]) -> [WorkspaceInfo] {
        let ids = Set(matches.map(\.window.windowId))
        guard !ids.isEmpty else { return [] }
        return workspaces.compactMap { workspace in
            var kept = workspace
            kept.windows = workspace.windows.filter { ids.contains($0.windowId) }
            return kept.windows.isEmpty ? nil : kept
        }
    }
}

/// The ordinal the digit keys pick, by window id, which is also the badge that tile draws.
/// One through nine; past the ninth match the mouse or another letter is the way.
public func filterOrdinals(matches: [ParsedWindow]) -> [Int: Int] {
    Dictionary(uniqueKeysWithValues: matches.prefix(9).enumerated().map { ($0.element.window.windowId, $0.offset + 1) })
}

/// A keystroke the overview understands, named by what it means rather than by its key code:
/// the mapping from an `NSEvent` is AppKit's job, and `Common` never sees one.
public enum FilterKey: Equatable, Sendable {
    case character(Character)
    case backspace
    case enter
    case escape
}

public extension FilterKey {
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
}

/// What a keystroke does to the filter. A digit 1–9 always selects and never types: making
/// it mean text *or* selection depending on the match count is what let `code2` focus a
/// window instead of narrowing the query, silently and with no way back. The cost is that a
/// digit cannot be searched for, which is why `0` is still text — nothing is ever labelled 0.
public func filterKeyAction(query: String, matches: [ParsedWindow], key: FilterKey) -> FilterKeyAction {
    switch key {
    case .escape:
        return query.isEmpty ? .none : .setQuery("")
    case .enter:
        return matches.count == 1 ? .focus(windowId: matches[0].window.windowId) : .none
    case .backspace:
        return query.isEmpty ? .none : .setQuery(String(query.dropLast()))
    case .character(let character):
        if character.isASCII, let ordinal = character.wholeNumberValue, (1...9).contains(ordinal) {
            // Out of range is inert rather than text: a digit means the same thing whether
            // or not there is a tile wearing it.
            guard ordinal <= matches.count else { return .none }
            return .focus(windowId: matches[ordinal - 1].window.windowId)
        }
        // A query is trimmed before it is matched, so one starting with a space shows a pill
        // with nothing in it over an unchanged grid, and the next Escape spends itself
        // clearing it. Internal spaces are text like any other ("cafe munster").
        guard !(query.isEmpty && character.isWhitespace) else { return .none }
        return .setQuery(query + String(character))
    }
}
