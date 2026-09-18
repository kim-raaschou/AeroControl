import Foundation

private extension String {
    /// Case- and diacritic-insensitive containment with the locale named explicitly. The
    /// locale-aware fold is a trap here: in a Turkish one "I" folds to "ı", so "Inbox" stops
    /// matching "i" — and a test in the host's locale would never see it.
    func foldedContains(_ needle: String) -> Bool {
        range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: nil, locale: nil) != nil
    }
}

public extension OverviewModel {
    /// Windows whose title or app name contains `query`, case- and diacritic-insensitively,
    /// each with the workspace it lives on. Title matches come first: part of a meeting name
    /// means that window, not the three other windows of the same app. Within each group
    /// AeroSpace's own order stands. An empty query matches nothing: the filter is off, not
    /// "everything".
    func matching(_ query: String) -> [ParsedWindow] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        let scored = workspaces.flatMap { workspace in
            workspace.windows.compactMap { window -> (match: ParsedWindow, byTitle: Bool)? in
                let byTitle = window.title.foldedContains(needle)
                guard byTitle || window.appName.foldedContains(needle) else { return nil }
                return (ParsedWindow(window: window, workspace: workspace.name), byTitle)
            }
        }
        return scored.filter(\.byTitle).map(\.match) + scored.filter { !$0.byTitle }.map(\.match)
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

/// The ordinal ⌘1…⌘9 picks, by window id, which is also the badge that tile draws. There are
/// only nine digits; past the ninth match the mouse or another letter is the way.
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

/// What a keystroke does to the filter. `matches` is the whole match list, and nothing here
/// reads it to pick a window by number: a plain digit is text, ⌘1…⌘9 selects.
public func filterKeyAction(query: String, matches: [ParsedWindow], key: FilterKey) -> FilterKeyAction {
    switch key {
    case .escape:
        return query.isEmpty ? .none : .setQuery("")
    case .enter:
        return matches.count == 1 ? .focus(windowId: matches[0].window.windowId) : .none
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
