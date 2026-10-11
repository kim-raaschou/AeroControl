import Testing
@testable import Common

private func ws(_ name: String, _ windows: WindowInfo...) -> WorkspaceInfo {
    WorkspaceInfo(name: name, windows: windows)
}

@Suite("Visit — a read")
struct LoadedTests {

    @Test("a load that says nothing is focused clears the ring")
    func loadedCanClearFocus() {
        var visit = Visit()
        _ = visit.apply(.loaded(OverviewModel(workspaces: [ws("1")], focusedWindowId: 9, focusedWorkspace: "1")))
        _ = visit.apply(.loaded(OverviewModel(workspaces: [ws("1")], focusedWorkspace: "4")))
        #expect(visit.model.focusedWindowId == 0 && visit.model.focusedWorkspace == "4")
    }
}

@Suite("OverviewModel — monitors")
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
