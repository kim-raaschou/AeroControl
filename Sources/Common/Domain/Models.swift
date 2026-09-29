import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public let windowId: Int
    public let appName: String
    public let bundleId: String
    public let isFloating: Bool
    public let isFullscreen: Bool
    public let title: String

    public init(windowId: Int, appName: String, bundleId: String, isFloating: Bool = false,
                isFullscreen: Bool = false, title: String = "") {
        self.windowId = windowId
        self.appName = appName
        self.bundleId = bundleId
        self.isFloating = isFloating
        self.isFullscreen = isFullscreen
        self.title = title
    }

    /// The title without the app's own name at its end — "README.md — Visual Studio Code"
    /// is "README.md": the icon says which app it is, and the title is the one thing that
    /// tells two windows of one app apart, so the name only pushes it out of the caption.
    /// A window with no title is named by its app.
    public var caption: String {
        let text = title.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return appName }
        for separator in [" — ", " – ", " - ", " | "] {
            let tail = separator + appName
            if text.count > tail.count, text.suffix(tail.count).lowercased() == tail.lowercased() {
                let head = text.dropLast(tail.count).trimmingCharacters(in: .whitespaces)
                return head.isEmpty ? appName : head
            }
        }
        return text
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
    /// AeroSpace's `monitor-appkit-nsscreen-screens-id`: 1-based into `NSScreen.screens`, 0
    /// when it did not say. The card takes that screen's shape.
    public var screenIndex: Int

    /// The first word of the display's name: "Built-in Retina Display" -> "Built-in",
    /// "BenQ RD280U" -> "BenQ". Enough to tell two displays apart in a card header, and
    /// short enough to fit beside the badge.
    public var monitorShortName: String {
        String(monitorName.split(separator: " ").first ?? "")
    }

    public init(name: String, windows: [WindowInfo], monitorId: Int = 1, monitorName: String = "", screenIndex: Int = 0) {
        self.name = name
        self.windows = windows
        self.monitorId = monitorId
        self.monitorName = monitorName
        self.screenIndex = screenIndex
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

