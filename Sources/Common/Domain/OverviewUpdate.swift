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

    public var monitors: [MonitorInfo] {
        Array(Set(workspaces.map(\.monitorId))).sorted().map { MonitorInfo(monitorId: $0) }
    }

    public func workspaces(forMonitor monitorId: Int) -> [WorkspaceInfo] {
        workspaces.filter { $0.monitorId == monitorId }
    }

    public func workspaces(forScreen nsScreenId: Int) -> [WorkspaceInfo] {
        workspaces.filter { $0.nsScreenId == nsScreenId }
    }
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
    case monitorsChanged
    case runAction(AeroControlAction)
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
    (state, [.runAction(action)])
}

private func applyLoaded(_ state: OverviewModel, _ result: OverviewResult) -> (OverviewModel, [OverviewEffect]) {
    let oldIds = Set(state.workspaces.flatMap(\.windows).map(\.windowId))
    let freshIds = Set(result.workspaces.flatMap(\.windows).map(\.windowId))

    var new = state
    new.workspaces = result.workspaces

    let removedIds = oldIds.subtracting(freshIds)
    var effects: [OverviewEffect] = removedIds.sorted().map { .windowRemoved($0) }
    let allWindows = new.workspaces.flatMap(\.windows)
    if !allWindows.isEmpty {
        effects.append(.loadIcons(allWindows))
    }
    if new.monitors != state.monitors {
        effects.append(.monitorsChanged)
    }
    return (new, effects)
}

private func applyEvent(_ state: OverviewModel, _ event: AerospaceEvent) -> (OverviewModel, [OverviewEffect]) {
    switch event {
    case .focusChanged(let windowId, let workspace):
        var new = state
        new.focusedWindowId = windowId ?? 0
        new.focusedWorkspace = workspace
        return (new, [.refresh])

    case .workspaceChanged(let workspace, _):
        var new = state
        new.focusedWorkspace = workspace
        return (new, [.refresh])

    case .monitorChanged(let workspace, _):
        var new = state
        new.focusedWorkspace = workspace
        return (new, [.refresh])

    case .windowDetected:
        return (state, [.refresh])

    case .localWindowClosed:
        return (state, [.refresh])

    case .bindingTriggered:
        return (state, [.refresh])

    case .other:
        return (state, [])
    }
}