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
    case windowRemoved(Int)
    case loadIcons([WindowInfo])
    case refresh
    case runAction(AeroControlAction)
    /// Actions that must run one after another, in order (e.g. a merge).
    case runSequence([AeroControlAction])
}

public func updateOverview(_ state: OverviewModel, _ input: OverviewInput) -> (OverviewModel, [OverviewEffect]) {
    switch input {
    case .loaded(let result):
        return applyLoaded(state, result)
    case .event(let event):
        return applyEvent(state, event)
    case .action(let action):
        return applyAction(state, action)
    }
}

private func applyAction(_ state: OverviewModel, _ action: AeroControlAction) -> (OverviewModel, [OverviewEffect]) {
    guard case .mergeWorkspace(let source, let target) = action else {
        return (state, [.runAction(action)])
    }
    guard source != target,
          let windows = state.workspaces.first(where: { $0.name == source })?.windows,
          !windows.isEmpty else {
        return (state, [])
    }
    let moves = windows.map { AeroControlAction.moveWindowQuietly(windowId: $0.windowId, toWorkspace: target) }
    return (state, [.runSequence(moves + [.focusWorkspace(target)])])
}

private func applyLoaded(_ state: OverviewModel, _ result: OverviewResult) -> (OverviewModel, [OverviewEffect]) {
    let oldIds = Set(state.workspaces.flatMap(\.windows).map(\.windowId))
    let freshIds = Set(result.workspaces.flatMap(\.windows).map(\.windowId))

    var new = state
    new.workspaces = result.workspaces
    if let focus = result.focus {
        new.focusedWindowId = focus.windowId
        new.focusedWorkspace = focus.workspace
    }

    let removedIds = oldIds.subtracting(freshIds)
    var effects: [OverviewEffect] = removedIds.sorted().map { .windowRemoved($0) }
    let allWindows = new.workspaces.flatMap(\.windows)
    if !allWindows.isEmpty {
        effects.append(.loadIcons(allWindows))
    }
    return (new, effects)
}

private func applyEvent(_ state: OverviewModel, _ event: AerospaceEvent) -> (OverviewModel, [OverviewEffect]) {
    switch event {
    case .changed, .localWindowClosed: (state, [.refresh])
    case .other: (state, [])
    }
}
