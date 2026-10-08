import CoreGraphics
import Testing
@testable import Common

@Suite("parseWindows")
struct ParseWindowsTests {
    @Test("parses valid JSON into ParsedWindow array, a missing title as empty; nothing, or an empty list, is no window")
    func parsesValidJson() throws {
        let json = """
        [
          {"window-id": 1, "app-name": "Firefox", "app-bundle-id": "org.mozilla.firefox", "window-title": "Inbox", "workspace": "1", "window-parent-container-layout": "h_tiles", "monitor-id": 1},
          {"window-id": 2, "app-name": "Terminal", "app-bundle-id": "com.apple.Terminal", "workspace": "2", "window-parent-container-layout": "floating", "monitor-id": 1}
        ]
        """
        let result = try parseWindows(json: json)
        #expect(result.map(\.window.windowId) == [1, 2] && result.map(\.workspace) == ["1", "2"])
        #expect(result[0].window.appName == "Firefox" && result[0].window.bundleId == "org.mozilla.firefox")
        #expect(result.map(\.window.title) == ["Inbox", ""])
        #expect(try parseWindows(json: "").isEmpty && parseWindows(json: "[]").isEmpty)
    }

    @Test("a window list decodes without a monitor-id, which only list-workspaces carries")
    func windowsCarryNoMonitor() throws {
        let json = """
        [
          {"window-id": 1, "app-name": "Firefox", "app-bundle-id": "org.mozilla.firefox", "workspace": "1", "window-parent-container-layout": "h_tiles"}
        ]
        """
        let result = try parseWindows(json: json)
        #expect(result.count == 1)
        #expect(result[0].workspace == "1")
    }
}

@Suite("parseWindows — state")
struct ParseWindowStateTests {
    @Test("a window's fullscreen flag is read; a list without it decodes as not fullscreen")
    func fullscreen() throws {
        let json = """
        [{"window-id": 1, "app-name": "Arc", "app-bundle-id": "company.thebrowser.Browser", "workspace": "1",
          "window-parent-container-layout": "h_tiles", "window-is-fullscreen": true},
         {"window-id": 2, "app-name": "Arc", "app-bundle-id": "company.thebrowser.Browser", "workspace": "1",
          "window-parent-container-layout": "h_tiles"}]
        """
        let windows = try parseWindows(json: json).map(\.window)
        #expect(windows.map(\.isFullscreen) == [true, false])
    }

    @Test("what AeroSpace says of a window's place is its state: floating, macOS fullscreen, minimized or its app hidden")
    func nativeStates() throws {
        let layouts = ["h_tiles", "floating", "macos_native_fullscreen", "macos_native_minimized", "macos_native_window_of_hidden_app"]
        let json = "[" + layouts.enumerated().map { i, layout in
            #"{"window-id": \#(i), "app-name": "A", "app-bundle-id": "a", "workspace": "1", "window-parent-container-layout": "\#(layout)"}"#
        }.joined(separator: ",") + "]"
        let windows = try parseWindows(json: json).map(\.window)
        #expect(windows.map(\.isFloating) == [false, true, false, false, false])
        #expect(windows.map(\.isFullscreen) == [false, false, true, false, false])
        #expect(windows.map(\.isHidden) == [false, false, false, true, true])
    }
}

@Suite("parseWorkspaces")
struct ParseWorkspacesTests {
    @Test("parses valid workspace JSON")
    func parsesValidJson() throws {
        let json = """
        [
          {"workspace": "1", "monitor-id": 1},
          {"workspace": "2", "monitor-id": 1},
          {"workspace": "3", "monitor-id": 2}
        ]
        """
        let result = try parseWorkspaces(json: json)
        #expect(result.count == 3)
        #expect(result[0].workspace == "1")
        #expect(result[0].monitorId == 1)
        #expect(result[2].monitorId == 2)
    }

    @Test("returns empty array for empty string")
    func emptyString() throws {
        let result = try parseWorkspaces(json: "")
        #expect(result.isEmpty)
    }

    @Test("the AppKit screen index is read, and a list without it decodes as 0")
    func screenIndex() throws {
        let json = """
        [{"workspace": "1", "monitor-id": 1, "monitor-name": "Built-in", "monitor-appkit-nsscreen-screens-id": 1},
         {"workspace": "2", "monitor-id": 2, "monitor-name": "BenQ", "monitor-appkit-nsscreen-screens-id": 2},
         {"workspace": "3", "monitor-id": 1}]
        """
        #expect(try parseWorkspaces(json: json).map(\.screenIndex) == [1, 2, 0])
        let built = buildOverviewResult(windows: [], workspaceMonitors: try parseWorkspaces(json: json))
        #expect(built.workspaces.map(\.screenIndex) == [1, 2, 0])
    }

    @Test("whether a workspace is visible is read; a list without it decodes as visible, so the map draws as it always has")
    func isVisible() throws {
        let json = """
        [{"workspace": "1", "monitor-id": 1, "workspace-is-visible": true}, {"workspace": "2", "monitor-id": 1, "workspace-is-visible": false}, {"workspace": "3", "monitor-id": 2}]
        """
        #expect(buildOverviewResult(windows: [], workspaceMonitors: try parseWorkspaces(json: json)).workspaces.map(\.isVisible) == [true, false, true])
    }

    @Test("tolerates string NULL-MONITOR-ID monitor-id")
    func nullMonitorSentinel() throws {
        let json = """
        [
          {"workspace": "1", "monitor-id": "NULL-MONITOR-ID"},
          {"workspace": "2", "monitor-id": 2}
        ]
        """
        let result = try parseWorkspaces(json: json)
        #expect(result.count == 2)
        #expect(result[0].monitorId == 0)
        #expect(result[1].monitorId == 2)
    }
}

@Suite("buildOverviewResult")
struct BuildOverviewResultTests {
    @Test("groups windows by workspace and sorts numerically")
    func groupsAndSorts() {
        let windows = [
            ParsedWindow(window: WindowInfo(windowId: 1, appName: "A", bundleId: "a"), workspace: "2"),
            ParsedWindow(window: WindowInfo(windowId: 2, appName: "B", bundleId: "b"), workspace: "1"),
            ParsedWindow(window: WindowInfo(windowId: 3, appName: "C", bundleId: "c"), workspace: "2"),
        ]
        let monitors = [
            WorkspaceMonitor(workspace: "1", monitorId: 1),
            WorkspaceMonitor(workspace: "2", monitorId: 1),
        ]
        let result = buildOverviewResult(windows: windows, workspaceMonitors: monitors)

        #expect(result.workspaces.count == 2)
        #expect(result.workspaces[0].name == "1")
        #expect(result.workspaces[0].windows.count == 1)
        #expect(result.workspaces[1].name == "2")
        #expect(result.workspaces[1].windows.count == 2)
    }

    @Test("workspace with no windows gets empty array")
    func emptyWorkspace() {
        let monitors = [WorkspaceMonitor(workspace: "5", monitorId: 1)]
        let result = buildOverviewResult(windows: [], workspaceMonitors: monitors)
        #expect(result.workspaces[0].windows.isEmpty)
    }

    @Test("multiple monitors are represented")
    func multipleMonitors() {
        let monitors = [
            WorkspaceMonitor(workspace: "1", monitorId: 1),
            WorkspaceMonitor(workspace: "2", monitorId: 2),
        ]
        let result = buildOverviewResult(windows: [], workspaceMonitors: monitors)
        #expect(Set(result.workspaces.map(\.monitorId)) == [1, 2])
    }
}

@Suite("a workspace's root layout")
struct RootLayoutTests {
    @Test("a workspace says how its root container is laid out; an older AeroSpace that does not still decodes")
    func decodes() throws {
        let json = """
        [{"workspace": "2", "monitor-id": 1, "workspace-root-container-layout": "h_tiles"},
         {"workspace": "3", "monitor-id": 1}]
        """
        let result = try parseWorkspaces(json: json)
        #expect(result[0].rootLayout == "h_tiles" && result[1].rootLayout == nil)
    }

    @Test("the overview result carries it on the workspace")
    func carried() {
        let monitors = [WorkspaceMonitor(workspace: "2", monitorId: 1, rootLayout: "v_accordion"), WorkspaceMonitor(workspace: "3", monitorId: 1)]
        let result = buildOverviewResult(windows: [], workspaceMonitors: monitors)
        #expect(result.workspaces[0].rootLayout == "v_accordion" && result.workspaces[1].rootLayout == "")
    }
}

@Suite("window-layout-rect")
struct LayoutRectTests {
    private func window(_ rect: String?) -> String {
        let field = rect.map { ", \"window-layout-rect\": \"\($0)\"" } ?? ""
        return """
        [{"window-id": 1, "app-name": "Ghostty", "app-bundle-id": "com.mitchellh.ghostty", "workspace": "7", "window-parent-container-layout": "h_tiles"\(field)}]
        """
    }

    @Test("x,y,width,height in points becomes the window's layout rect")
    func parsed() throws {
        let w = try parseWindows(json: window("16,48,842,1052"))[0].window
        #expect(w.layoutRect == CGRect(x: 16, y: 48, width: 842, height: 1052))
    }

    @Test("empty (a float, a fullscreen window in front), absent (a release AeroSpace) or malformed is no rect")
    func absent() throws {
        #expect(try parseWindows(json: window(""))[0].window.layoutRect == nil)
        #expect(try parseWindows(json: window(nil))[0].window.layoutRect == nil)
        #expect(try parseWindows(json: window("16,48"))[0].window.layoutRect == nil)
        #expect(try parseWindows(json: window("a,b,c,d"))[0].window.layoutRect == nil)
    }
}

@Suite("a workspace's windows in the layout's order")
struct LayoutOrderTests {
    private func w(_ id: Int, _ app: String, _ rect: String?) -> String {
        let field = rect.map { ", \"window-layout-rect\": \"\($0)\"" } ?? ""
        return #"{"window-id": \#(id), "app-name": "\#(app)", "app-bundle-id": "com.\#(app)", "workspace": "4", "window-parent-container-layout": "h_tiles"\#(field)}"#
    }

    @Test("with AeroSpace's rects a workspace's windows come in the layout's order, floats and windows without a rect after them")
    func ordered() throws {
        let json = "[" + [w(10916, "Ghostty", "1726,48,1698,1375"), w(10776, "Mail", "16,48,1698,1375"), w(5, "Finder", "")].joined(separator: ",") + "]"
        let result = buildOverviewResult(windows: try parseWindows(json: json), workspaceMonitors: [WorkspaceMonitor(workspace: "4", monitorId: 1)])
        #expect(result.workspaces[0].windows.map(\.windowId) == [10776, 10916, 5])
    }

    @Test("without rects the listing's order stands")
    func listingOrder() throws {
        let json = "[" + [w(10916, "Ghostty", nil), w(10776, "Mail", nil)].joined(separator: ",") + "]"
        let result = buildOverviewResult(windows: try parseWindows(json: json), workspaceMonitors: [WorkspaceMonitor(workspace: "4", monitorId: 1)])
        #expect(result.workspaces[0].windows.map(\.windowId) == [10916, 10776])
    }
}
