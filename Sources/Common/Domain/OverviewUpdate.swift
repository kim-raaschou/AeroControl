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

public enum OverviewInput {
    case loaded(OverviewResult)
    case event(AerospaceEvent)
    case action(AeroControlAction)
    case windowsValidated(liveIds: Set<Int>)
}

public enum OverviewEffect: Equatable {
    case windowRemoved(Int)
    case loadIcons([WindowInfo])
    case validateWindows
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
    case .windowsValidated(let liveIds):
        return applyValidation(state, liveIds: liveIds)
    }
}

/// User-initiated actions. The reducer decides the optimistic in-model change (if any)
/// and always emits `.runAction` so the interpreter executes the matching aerospace CLI
/// command. Post-CLI reconciliation (e.g. refreshing after a close) is the interpreter's
/// job since it is inherently asynchronous I/O.
private func applyAction(_ state: OverviewModel, _ action: AeroControlAction) -> (OverviewModel, [OverviewEffect]) {
    switch action {
    case .focusWorkspace, .focusWindow:
        return (state, [.runAction(action)])

    case .closeWindow(let windowId):
        // Optimistically remove the tile so closing feels instant instead of waiting for
        // the app (and macOS) to actually tear the window down. The interpreter
        // reconciles afterwards and restores the tile if the close didn't take (e.g. the
        // app kept it open for an unsaved-changes prompt).
        let (new, removed) = removeWindow(state, windowId)
        return removed
            ? (new, [.windowRemoved(windowId), .runAction(action)])
            : (state, [.runAction(action)])

    case .moveWindow(let windowId, let workspace):
        // Optimistically reflect the move so the UI updates instantly instead of waiting
        // for the event stream. Focus follows the moved window (CLI uses
        // --focus-follows-window), so update the focused workspace too.
        var (new, _) = moveWindow(state, windowId, to: workspace)
        new.focusedWorkspace = workspace
        return (new, [.runAction(action)])
    }
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

    case .appTerminated:
        return (state, [.validateWindows])

    case .bindingTriggered:
        return (state, [.refresh])

    case .other:
        return (state, [])
    }
}

private func sortWorkspacesNumerically(_ workspaces: inout [WorkspaceInfo]) {
    workspaces.sort { (Int($0.name) ?? .max) < (Int($1.name) ?? .max) }
}

/// Removes a window from whichever workspace holds it, returning the new model and
/// whether a window was actually found and removed.
private func removeWindow(_ state: OverviewModel, _ windowId: Int) -> (OverviewModel, Bool) {
    var new = state
    for (i, ws) in new.workspaces.enumerated() {
        if let j = ws.windows.firstIndex(where: { $0.windowId == windowId }) {
            new.workspaces[i].windows.remove(at: j)
            return (new, true)
        }
    }
    return (new, false)
}

private func moveWindow(_ state: OverviewModel, _ windowId: Int, to workspace: String) -> (OverviewModel, [OverviewEffect]) {
    var new = state
    for (i, ws) in new.workspaces.enumerated() {
        if let j = ws.windows.firstIndex(where: { $0.windowId == windowId }) {
            if ws.name == workspace { return (new, []) }

            var windows = new.workspaces[i].windows
            let window = windows.remove(at: j)
            new.workspaces[i].windows = windows

            if let targetIdx = new.workspaces.firstIndex(where: { $0.name == workspace }) {
                new.workspaces[targetIdx].windows.append(window)
            } else {
                // New workspace from move — inherit source monitor
                new.workspaces.append(WorkspaceInfo(name: workspace, windows: [window], monitorId: ws.monitorId))
                sortWorkspacesNumerically(&new.workspaces)
            }

            return (new, [])
        }
    }
    return (new, [])
}

private func applyValidation(_ state: OverviewModel, liveIds: Set<Int>) -> (OverviewModel, [OverviewEffect]) {
    guard !liveIds.isEmpty else { return (state, []) }

    var new = state
    var effects: [OverviewEffect] = []

    for (i, ws) in new.workspaces.enumerated() {
        let alive = ws.windows.filter { liveIds.contains($0.windowId) }
        if alive.count < ws.windows.count {
            let removedIds = Set(ws.windows.map(\.windowId)).subtracting(alive.map(\.windowId))
            for id in removedIds.sorted() {
                effects.append(.windowRemoved(id))
            }
            new.workspaces[i].windows = alive
        }
    }

    return (new, effects)
}