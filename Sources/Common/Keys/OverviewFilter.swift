import Foundation

private extension String {
    var words: [Substring] { split(whereSeparator: { !$0.isLetter && !$0.isNumber }) }

    func hasWordsStarting(with needles: [Substring]) -> Bool {
        let words = self.words
        return needles.allSatisfy { needle in
            words.contains { word in
                word.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .anchored],
                           range: nil, locale: nil) != nil
            }
        }
    }
}

public extension OverviewModel {
    static var minQueryLength: Int { 2 }

    func matching(_ query: String) -> [ParsedWindow] {
        let needles = query.words
        guard query.trimmingCharacters(in: .whitespaces).count >= Self.minQueryLength, !needles.isEmpty else { return [] }
        return windowsInGridOrder.filter { "\($0.window.title) \($0.window.appName) \($0.workspace)".hasWordsStarting(with: needles) }
    }

    var windowsInGridOrder: [ParsedWindow] {
        workspaces.flatMap { workspace in workspace.windows.map { ParsedWindow(window: $0, workspace: workspace.name) } }
    }

    func windows(of marking: Strip?) -> [ParsedWindow] {
        windowsInGridOrder.filter { marking?.owns($0.window) ?? true }
    }

    var focusedWindow: WindowInfo? {
        workspaces.lazy.flatMap(\.windows).first { $0.windowId == focusedWindowId }
    }

    func workspaces(holding matches: [ParsedWindow]) -> [WorkspaceInfo] {
        let ids = Set(matches.map(\.window.windowId))
        guard !ids.isEmpty else { return [] }
        return workspaces.compactMap { workspace in
            let kept = workspace.windows.filter { ids.contains($0.windowId) }
            return kept.isEmpty ? nil : workspace.with(windows: kept)
        }
    }
}

public enum FilterKey: Equatable, Sendable {
    case character(Character)
    case backspace
    case enter
    case escape
    case move(StripMove)
    case commandKey(Int)
    case moveToWorkspace(String)
}

public extension FilterKey {
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

    public static let windowKeys: [Character] = Array("123456789abcdef")

    public static func workspaceNamed(_ key: String) -> String? {
        guard key.count == 1, let c = key.first, typed(c) != nil else { return nil }
        return ["0": "10"][key] ?? key
    }

    private static let commandKeys: [String: FilterKey] = Dictionary(uniqueKeysWithValues: windowKeys.enumerated().map { (String($1), .commandKey($0 + 1)) })
        .merging(["\u{F703}": .move(.workspace(1)), "\u{F702}": .move(.workspace(-1)), "\u{F700}": .move(.workspaceRow(-1)), "\u{F701}": .move(.workspaceRow(1))]) { a, _ in a }

    init?(command characters: String, shift: Bool) {
        guard let key = shift ? Self.workspaceNamed(characters).map(FilterKey.moveToWorkspace) : Self.commandKeys[characters] else { return nil }
        self = key
    }

    static func typed(_ character: Character) -> FilterKey? {
        guard let scalar = character.unicodeScalars.first,
              !CharacterSet.controlCharacters.contains(scalar),
              scalar.value < 0xF700 else { return nil }
        return .character(character)
    }
}

public enum FilterKeyAction: Equatable, Sendable {
    case none
    case setQuery(String)
    case focus(windowId: Int)
    case handled
}

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
        guard !(query.isEmpty && character.isWhitespace) else { return .none }
        return .setQuery(query + String(character))
    }
}
