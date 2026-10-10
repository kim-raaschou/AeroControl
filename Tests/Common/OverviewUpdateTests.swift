import Testing
@testable import Common

private func window(_ id: Int, _ app: String) -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "")
}

private func ws(_ name: String, _ windows: WindowInfo...) -> WorkspaceInfo {
    WorkspaceInfo(name: name, windows: windows)
}

private func windowIds(_ state: OverviewModel, workspace: String) -> [Int] {
    state.workspaces.first(where: { $0.name == workspace })?.windows.map(\.windowId) ?? []
}

@Suite("update — loaded")
struct LoadedTests {

    @Test("a load that says nothing is focused clears the ring")
    func loadedCanClearFocus() {
        let s = OverviewModel(workspaces: [ws("1")], focusedWindowId: 9, focusedWorkspace: "1")
        let (new, _) = updateOverview(s, .loaded(OverviewResult(workspaces: [ws("1")], focus: Focus(workspace: "4"))))

        #expect(new.focusedWindowId == 0)
        #expect(new.focusedWorkspace == "4")
    }
}

@Suite("update — event")
struct EventTests {

}

@Suite("update — action")
struct ActionTests {

}

@Suite("update — monitors")
struct MonitorNamingTests {
    private func ws(_ name: String, monitor: Int) -> WorkspaceInfo {
        WorkspaceInfo(name: name, windows: [], monitorId: monitor, monitorName: "Display \(monitor)")
    }

    @Test("a workspace carries its display's name, and cards name it only when displays differ")
    func spansMonitors() {
        #expect(!OverviewModel().spansMonitors)                                  // nothing loaded
        #expect(!OverviewModel(workspaces: [ws("1", monitor: 1), ws("2", monitor: 1)]).spansMonitors)
        let two = OverviewModel(workspaces: [ws("1", monitor: 1), ws("5", monitor: 2)])
        #expect(two.spansMonitors)
        #expect(two.workspaces.map(\.monitorName) == ["Display 1", "Display 2"])
    }
}
