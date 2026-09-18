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
    /// AeroSpace's own order inside each. That order is the one Tab walks, and its first
    /// entry is what Enter picks until Tab says otherwise. A query shorter than
    /// `minQueryLength` matches nothing: the filter is not on yet, which is not the same as
    /// matching everything.
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

public extension Array where Element == ParsedWindow {
    /// The match the ring is on: `selection` clamped to the last one, nil when there is none.
    /// The one place that turns an index into a match — a list that shrank under a stale
    /// index (a window closed while the query stood) still wears a ring, and Enter picks
    /// exactly what the ring shows, because both ask here.
    func selected(_ selection: Int) -> ParsedWindow? {
        isEmpty ? nil : self[Swift.min(selection, count - 1)]
    }
}

/// A keystroke the overview understands, named by what it means rather than by its key code:
/// the mapping from an `NSEvent` is AppKit's job, and `Common` never sees one.
public enum FilterKey: Equatable, Sendable {
    case character(Character)
    case backspace
    case enter
    case escape
    /// Tab and →, Shift-Tab and ←: the ring moves to the next or previous match.
    case next
    case previous
}

public extension FilterKey {
    /// The key a keyboard event stands for, from the parts of it that matter; nil when it is
    /// not one of ours. The caller has already ruled out Cmd, Ctrl and Option. Shift is not
    /// a modifier here: it is how capitals are typed, and how Tab is walked backwards.
    init?(keyCode: UInt16, shift: Bool, characters: String?) {
        switch keyCode {
        case 53: self = .escape
        case 51: self = .backspace
        case 36, 76: self = .enter
        case 48: self = shift ? .previous : .next
        case 124: self = .next
        case 123: self = .previous
        default:
            guard let key = characters?.first.flatMap(FilterKey.typed) else { return nil }
            self = key
        }
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
    /// The ring moves to this index of the matches.
    case select(Int)
    case focus(windowId: Int)
}

/// What a keystroke does to the filter. `selection` is the match the ring is on: Enter picks
/// it, Tab and the arrows move it and wrap at either end. Everything typed is text, digits
/// included — "code2" narrows the query and nothing else. A match is picked by typing until
/// it is first, or by walking the ring to it; there is nothing on screen to read a key off.
public func filterKeyAction(query: String, matches: [ParsedWindow], selection: Int, key: FilterKey) -> FilterKeyAction {
    switch key {
    case .escape:
        return query.isEmpty ? .none : .setQuery("")
    case .enter:
        guard let pick = matches.selected(selection) else { return .none }
        return .focus(windowId: pick.window.windowId)
    case .next, .previous:
        // One match has nowhere to go; none has nothing to stand on.
        guard matches.count > 1 else { return .none }
        let at = Swift.min(selection, matches.count - 1)
        return .select((at + (key == .next ? 1 : -1) + matches.count) % matches.count)
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
