import Foundation

public struct OverviewModel: Equatable, Sendable {
    public var workspaces: [WorkspaceInfo]
    public var focusedWindowId: Int
    public var focusedWorkspace: String

    public init(
        workspaces: [WorkspaceInfo] = [],
        focusedWindowId: Int = 0,
        focusedWorkspace: String = ""
    ) {
        self.workspaces = workspaces
        self.focusedWindowId = focusedWindowId
        self.focusedWorkspace = focusedWorkspace
    }
}

public extension OverviewModel {
    var spansMonitors: Bool { Set(workspaces.map(\.monitorId)).count > 1 }
}

public extension OverviewModel {
    static func isQuery(_ query: String) -> Bool { query.trimmingCharacters(in: .whitespaces).count >= 2 }

    func matching(_ query: String) -> [WindowInfo] {
        let needles = query.words
        guard Self.isQuery(query), !needles.isEmpty else { return [] }
        return windowsInGridOrder.filter { "\($0.title) \($0.appName) \($0.workspace)".hasWordsStarting(with: needles) }
    }

    var windowsInGridOrder: [WindowInfo] { workspaces.flatMap(\.windows) }

    func window(_ id: Int) -> WindowInfo? { workspaces.lazy.flatMap(\.windows).first { $0.windowId == id } }

    var focusedWindow: WindowInfo? { window(focusedWindowId) }

    func workspaces(holding matches: [WindowInfo]) -> [WorkspaceInfo] {
        let ids = Set(matches.map(\.windowId))
        guard !ids.isEmpty else { return [] }
        return workspaces.compactMap { workspace in
            let kept = workspace.windows.filter { ids.contains($0.windowId) }
            return kept.isEmpty ? nil : workspace.with(windows: kept)
        }
    }
}

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
