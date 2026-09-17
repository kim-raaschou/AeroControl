import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public let windowId: Int
    public let appName: String
    public let bundleId: String
    public let isFloating: Bool
    public let title: String

    public init(windowId: Int, appName: String, bundleId: String, isFloating: Bool = false, title: String = "") {
        self.windowId = windowId
        self.appName = appName
        self.bundleId = bundleId
        self.isFloating = isFloating
        self.title = title
    }
}

public struct WorkspaceInfo: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public var windows: [WindowInfo]
    public var monitorId: Int
    /// The display AeroSpace put this workspace on, e.g. "BenQ RD280U"; shown only when
    /// there is more than one.
    public var monitorName: String

    /// The first word of the display's name: "Built-in Retina Display" -> "Built-in",
    /// "BenQ RD280U" -> "BenQ". Enough to tell two displays apart in a card header, and
    /// short enough to fit beside the badge.
    public var monitorShortName: String {
        String(monitorName.split(separator: " ").first ?? "")
    }

    public init(name: String, windows: [WindowInfo], monitorId: Int = 1, monitorName: String = "") {
        self.name = name
        self.windows = windows
        self.monitorId = monitorId
        self.monitorName = monitorName
    }
}


/// What AeroSpace considers focused. Asked for separately from the window list because a
/// workspace with no windows is still the focused one.
public struct Focus: Equatable, Sendable {
    public let windowId: Int
    public let workspace: String

    public init(windowId: Int = 0, workspace: String = "") {
        self.windowId = windowId
        self.workspace = workspace
    }
}

public struct OverviewResult: Equatable, Sendable {
    public let workspaces: [WorkspaceInfo]
    /// `nil` when AeroSpace did not answer the focus reads — leave focus as it was rather
    /// than wiping it. A present-but-empty `Focus` is an answer: nothing is focused.
    public let focus: Focus?

    public init(workspaces: [WorkspaceInfo], focus: Focus? = nil) {
        self.workspaces = workspaces
        self.focus = focus
    }
}

