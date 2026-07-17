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

    /// The distinct monitors currently hosting workspaces, ascending by id. Derived
    /// from `workspaces`: a monitor exists exactly when it has at least one workspace,
    /// so there is no separate monitor state to keep in sync.
    public var monitors: [MonitorInfo] {
        Array(Set(workspaces.map(\.monitorId))).sorted().map { MonitorInfo(monitorId: $0) }
    }

    /// Workspaces filtered for a specific monitor.
    public func workspaces(forMonitor monitorId: Int) -> [WorkspaceInfo] {
        workspaces.filter { $0.monitorId == monitorId }
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

/// User-initiated actions. The model never predicts the outcome — AeroSpace is the
/// source of truth. Each action only emits `.runAction` so the interpreter executes the
/// matching aerospace CLI command; the interpreter then reloads and the resulting event
/// (or its own post-command refresh) mirrors reality back into the model.
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
        // Reconcile against reality on every workspace switch: the workspace we just
        // left (prevWorkspace) may now be empty and pruned by AeroSpace, so reload to
        // keep the current and previous workspaces in sync with the source of truth.
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