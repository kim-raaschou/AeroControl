import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public let windowId: Int
    public let appName: String
    public let bundleId: String
    public let isFloating: Bool
    public let isFullscreen: Bool
    /// Out of the layout and on no screen, by AeroSpace's word: minimized, or its app hidden (⌘H).
    public let isHidden: Bool
    public let title: String
    /// Where AeroSpace's layout last put the window, in screen points with a top-left origin
    /// (`%{window-layout-rect}`, the owner's AeroSpace branch). Nil on a release AeroSpace,
    /// for a floating window, and for a fullscreen window in front.
    public let layoutRect: CGRect?

    public init(windowId: Int, appName: String, bundleId: String, isFloating: Bool = false,
                isFullscreen: Bool = false, isHidden: Bool = false, title: String = "", layoutRect: CGRect? = nil) {
        self.windowId = windowId
        self.appName = appName
        self.bundleId = bundleId
        self.isFloating = isFloating
        self.isFullscreen = isFullscreen
        self.isHidden = isHidden
        self.layoutRect = layoutRect
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
    public let windows: [WindowInfo]
    public let monitorId: Int
    /// The display AeroSpace put this workspace on, e.g. "BenQ RD280U"; shown only when
    /// there is more than one.
    public let monitorName: String
    /// AeroSpace's `monitor-appkit-nsscreen-screens-id`: 1-based into `NSScreen.screens`, 0
    /// when it did not say. The card takes that screen's shape.
    public let screenIndex: Int
    /// How AeroSpace lays out the workspace's root container: `h_tiles`, `v_tiles`, `h_accordion` or
    /// `v_accordion`. Empty when AeroSpace did not say.
    public let rootLayout: String
    /// Whether it is the workspace shown on its monitor. Its windows are where AeroSpace put them
    /// only then; hidden, they are parked in a corner at the size they last had.
    public let isVisible: Bool

    /// The first word of the display's name: "Built-in Retina Display" -> "Built-in",
    /// "BenQ RD280U" -> "BenQ". Enough to tell two displays apart in a card header, and
    /// short enough to fit beside the badge.
    public var monitorShortName: String {
        String(monitorName.split(separator: " ").first ?? "")
    }

    public init(name: String, windows: [WindowInfo], monitorId: Int = 1, monitorName: String = "", screenIndex: Int = 0,
                rootLayout: String = "", isVisible: Bool = true) {
        self.name = name
        self.windows = windows
        self.monitorId = monitorId
        self.monitorName = monitorName
        self.screenIndex = screenIndex
        self.rootLayout = rootLayout
        self.isVisible = isVisible
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

/// A window with the workspace it sits on, as `list-windows` reports it; also what the
/// overview's filter hands back for a match, which needs exactly the same pair.
public struct ParsedWindow: Equatable {
    public let window: WindowInfo
    public let workspace: String

    public init(window: WindowInfo, workspace: String) {
        self.window = window
        self.workspace = workspace
    }
}
