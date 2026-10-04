import Foundation

public struct OverviewModel: Equatable {
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
    /// True when the workspaces span more than one display, the only case where naming a
    /// workspace's display tells the reader anything.
    var spansMonitors: Bool { Set(workspaces.map(\.monitorId)).count > 1 }
}

public enum OverviewInput: Sendable {
    case loaded(OverviewResult)
    case event(AerospaceEvent)
    case action(AeroControlAction)
}

public enum OverviewEffect: Equatable {
    case refresh
    /// AeroSpace commands one after another, in order (a merge keeps the tiling order and focuses
    /// last), then, `thenRead`, AeroSpace read again. A focus is not read after: the overview
    /// closes on it.
    case run([AeroControlAction], thenRead: Bool)
}

public func updateOverview(_ state: OverviewModel, _ input: OverviewInput) -> (OverviewModel, [OverviewEffect]) {
    var new = state
    switch input {
    case .loaded(let result):
        new.workspaces = result.workspaces
        if let focus = result.focus {
            new.focusedWindowId = focus.windowId
            new.focusedWorkspace = focus.workspace
        }
        return (new, [])
    case .event(.focusChanged(let windowId, let workspace)):
        new.focusedWindowId = windowId ?? 0
        new.focusedWorkspace = workspace
        return (new, [.refresh])
    case .event(.changed):
        return (state, [.refresh])
    case .action(.mergeWorkspace(let source, let target)):
        let windows = source == target ? [] : state.workspaces.first { $0.name == source }?.windows ?? []
        guard !windows.isEmpty else { return (state, []) }
        return (state, [.run(windows.map { .moveWindowQuietly(windowId: $0.windowId, toWorkspace: target) } + [.focusWorkspace(target)], thenRead: true)])
    case .action(let action):
        return (state, [.run([action], thenRead: !action.isFocus)])
    }
}
