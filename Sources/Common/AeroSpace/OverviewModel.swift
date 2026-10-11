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
