import CoreGraphics
import Testing
@testable import Common

@Suite("parseWindows")
struct ParseWindowsTests {
    @Test("parses valid JSON into windows, a missing title as empty; nothing, or an empty list, is no window")
    func parsesValidJson() throws {
        let json = """
        [
          {"window-id": 1, "app-name": "Firefox", "app-bundle-id": "org.mozilla.firefox", "window-title": "Inbox", "workspace": "1", "window-parent-container-layout": "h_tiles", "monitor-id": 1},
          {"window-id": 2, "app-name": "Terminal", "app-bundle-id": "com.apple.Terminal", "workspace": "2", "window-parent-container-layout": "floating", "monitor-id": 1}
        ]
        """
        let result = try parseWindows(json: json)
        #expect(result.map(\.windowId) == [1, 2] && result.map(\.workspace) == ["1", "2"])
        #expect(result[0].appName == "Firefox" && result[0].bundleId == "org.mozilla.firefox")
        #expect(result.map(\.title) == ["Inbox", ""])
        #expect(try parseWindows(json: "").isEmpty && parseWindows(json: "[]").isEmpty)
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
        let windows = try parseWindows(json: json)
        #expect(windows.map(\.isFullscreen) == [true, false])
    }

    @Test("what AeroSpace says of a window's place is its state: floating, macOS fullscreen, minimized or its app hidden")
    func nativeStates() throws {
        let layouts = ["h_tiles", "floating", "macos_native_fullscreen", "macos_native_minimized", "macos_native_window_of_hidden_app"]
        let json = "[" + layouts.enumerated().map { i, layout in
            #"{"window-id": \#(i), "app-name": "A", "app-bundle-id": "a", "workspace": "1", "window-parent-container-layout": "\#(layout)"}"#
        }.joined(separator: ",") + "]"
        let windows = try parseWindows(json: json)
        #expect(windows.map(\.isFloating) == [false, true, false, false, false])
        #expect(windows.map(\.isFullscreen) == [false, false, true, false, false])
        #expect(windows.map(\.isHidden) == [false, false, false, true, true])
    }
}

@Suite("parseWorkspaces")
struct ParseWorkspacesTests {
    @Test("the AppKit screen index is read, and a list without it decodes as 0")
    func screenIndex() throws {
        let json = """
        [{"workspace": "1", "monitor-id": 1, "monitor-name": "Built-in", "monitor-appkit-nsscreen-screens-id": 1},
         {"workspace": "2", "monitor-id": 2, "monitor-name": "BenQ", "monitor-appkit-nsscreen-screens-id": 2},
         {"workspace": "3", "monitor-id": 1}]
        """
        #expect(try parseWorkspaces(json: json).map(\.screenIndex) == [1, 2, 0])
        let built = buildOverview(windows: [], workspaceMonitors: try parseWorkspaces(json: json))
        #expect(built.workspaces.map(\.screenIndex) == [1, 2, 0])
    }
}

@Suite("buildOverview")
struct BuildOverviewTests {
    @Test("the workspaces in list-workspaces' order, each with its windows, its monitor and its root layout, one with no windows too, one with no monitor; no text is no workspace")
    func built() throws {
        let windows = [
            WindowInfo(windowId: 1, appName: "A", bundleId: "a", workspace: "2"),
            WindowInfo(windowId: 2, appName: "B", bundleId: "b", workspace: "1"),
            WindowInfo(windowId: 3, appName: "C", bundleId: "c", workspace: "2"),
        ]
        let monitors = try parseWorkspaces(json: """
        [{"workspace": "2", "monitor-id": 1, "workspace-root-container-layout": "v_accordion"},
         {"workspace": "1", "monitor-id": 2},
         {"workspace": "5", "monitor-id": 2},
         {"workspace": "6", "monitor-id": "NULL-MONITOR-ID"}]
        """)
        let result = buildOverview(windows: windows, workspaceMonitors: monitors)
        #expect(result.workspaces.map(\.name) == ["2", "1", "5", "6"] && result.workspaces.map { $0.windows.map(\.windowId) } == [[1, 3], [2], [], []])
        #expect(result.workspaces.map(\.monitorId) == [1, 2, 2, 0] && result.workspaces.map(\.rootLayout) == ["v_accordion", "", "", ""])
        #expect(try parseWorkspaces(json: "").isEmpty)
    }
}

private func windowJSON(_ id: Int, _ app: String, _ rect: String?) -> String {
    let field = rect.map { ", \"window-layout-rect\": \"\($0)\"" } ?? ""
    return #"{"window-id": \#(id), "app-name": "\#(app)", "app-bundle-id": "com.\#(app)", "workspace": "4", "window-parent-container-layout": "h_tiles"\#(field)}"#
}

@Suite("window-layout-rect")
struct LayoutRectTests {
    private func window(_ rect: String?) -> String { "[" + windowJSON(1, "Ghostty", rect) + "]" }

    @Test("x,y,width,height in points becomes the window's layout rect")
    func parsed() throws {
        let w = try parseWindows(json: window("16,48,842,1052"))[0]
        #expect(w.layoutRect == CGRect(x: 16, y: 48, width: 842, height: 1052))
    }

    @Test("empty (a float, a fullscreen window in front), absent (a release AeroSpace) or malformed is no rect")
    func absent() throws {
        #expect(try parseWindows(json: window(""))[0].layoutRect == nil)
        #expect(try parseWindows(json: window(nil))[0].layoutRect == nil)
        #expect(try parseWindows(json: window("16,48"))[0].layoutRect == nil)
        #expect(try parseWindows(json: window("a,b,c,d"))[0].layoutRect == nil)
    }
}

@Suite("a workspace's windows in the layout's order")
struct LayoutOrderTests {
    @Test("with AeroSpace's rects a workspace's windows come in the layout's order, floats and windows without a rect after them")
    func ordered() throws {
        let json = "[" + [windowJSON(10916, "Ghostty", "1726,48,1698,1375"), windowJSON(10776, "Mail", "16,48,1698,1375"), windowJSON(5, "Finder", "")].joined(separator: ",") + "]"
        let result = buildOverview(windows: try parseWindows(json: json), workspaceMonitors: try parseWorkspaces(json: #"[{"workspace": "4", "monitor-id": 1}]"#))
        #expect(result.workspaces[0].windows.map(\.windowId) == [10776, 10916, 5])
    }

    @Test("without rects the listing's order stands")
    func listingOrder() throws {
        let json = "[" + [windowJSON(10916, "Ghostty", nil), windowJSON(10776, "Mail", nil)].joined(separator: ",") + "]"
        let result = buildOverview(windows: try parseWindows(json: json), workspaceMonitors: try parseWorkspaces(json: #"[{"workspace": "4", "monitor-id": 1}]"#))
        #expect(result.workspaces[0].windows.map(\.windowId) == [10916, 10776])
    }
}
