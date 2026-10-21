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

    @Test("a summon while the last visit is still closing is a visit of its own: from another app the app's key goes straight to its window")
    func freshWhileClosing() {
        var visit = Visit()
        let slack = { (id: Int) in WindowInfo(windowId: id, appName: "Slack", bundleId: "com.slack") }, app = Summon.app(.bundleId("com.slack"))
        _ = visit.apply(.loaded(OverviewModel(workspaces: [ws("1", WindowInfo(windowId: 1, appName: "Code", bundleId: "com.code"), slack(2), slack(3))], focusedWindowId: 1, focusedWorkspace: "1")))
        _ = visit.summon(.map, drawn: []); _ = visit.summoned(.map)
        _ = visit.hide(restoreFocus: false)
        _ = visit.summon(app, drawn: []); _ = visit.summoned(app)
        #expect(visit.strip == nil && !visit.visible)
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
        #expect(OverviewModel(workspaces: [ws("1", monitor: 1), ws("5", monitor: 2)]).spansMonitors)
    }
}
