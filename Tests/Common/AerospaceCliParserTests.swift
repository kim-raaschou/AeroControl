import Testing
@testable import Common

@Suite("parseWindows")
struct ParseWindowsTests {
    @Test("parses valid JSON into ParsedWindow array")
    func parsesValidJson() throws {
        let json = """
        [
          {"window-id": 1, "app-name": "Firefox", "app-bundle-id": "org.mozilla.firefox", "workspace": "1", "window-parent-container-layout": "h_tiles", "monitor-id": 1},
          {"window-id": 2, "app-name": "Terminal", "app-bundle-id": "com.apple.Terminal", "workspace": "2", "window-parent-container-layout": "floating", "monitor-id": 1}
        ]
        """
        let result = try parseWindows(json: json)
        #expect(result.count == 2)
        #expect(result[0].window.windowId == 1)
        #expect(result[0].window.appName == "Firefox")
        #expect(result[0].window.bundleId == "org.mozilla.firefox")
        #expect(result[0].window.isFloating == false)
        #expect(result[0].workspace == "1")
        #expect(result[1].window.isFloating == true)
        #expect(result[1].workspace == "2")
    }

    @Test("returns empty array for empty string")
    func emptyString() throws {
        let result = try parseWindows(json: "")
        #expect(result.isEmpty)
    }

    @Test("returns empty array for empty JSON array")
    func emptyArray() throws {
        let result = try parseWindows(json: "[]")
        #expect(result.isEmpty)
    }

    @Test("tolerates string NULL-MONITOR monitor-id without failing the whole decode")
    func nullMonitorSentinel() throws {
        let json = """
        [
          {"window-id": 1, "app-name": "Firefox", "app-bundle-id": "org.mozilla.firefox", "workspace": "1", "window-parent-container-layout": "h_tiles", "monitor-id": "NULL-MONITOR"},
          {"window-id": 2, "app-name": "Terminal", "app-bundle-id": "com.apple.Terminal", "workspace": "2", "window-parent-container-layout": "v_accordion", "monitor-id": 2}
        ]
        """
        let result = try parseWindows(json: json)
        #expect(result.count == 2)
        #expect(result[0].monitorId == 0)
        #expect(result[1].monitorId == 2)
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
            ParsedWindow(window: WindowInfo(windowId: 1, appName: "A", bundleId: "a"), workspace: "2", monitorId: 1),
            ParsedWindow(window: WindowInfo(windowId: 2, appName: "B", bundleId: "b"), workspace: "1", monitorId: 1),
            ParsedWindow(window: WindowInfo(windowId: 3, appName: "C", bundleId: "c"), workspace: "2", monitorId: 1),
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
