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

    @Test("a load replaces the workspaces and brings focus with it")
    func loadedBasic() {
        let result = OverviewResult(
            workspaces: [ws("1", window(603, "Warp"), window(10159, "Arc")), ws("2", window(9009, "IDEA"))],
            focus: Focus(windowId: 9009, workspace: "2")
        )

        let (new, effects) = updateOverview(OverviewModel(), .loaded(result))

        #expect(windowIds(new, workspace: "1") == [603, 10159])
        #expect(windowIds(new, workspace: "2") == [9009])
        #expect(new.focusedWindowId == 9009)
        #expect(new.focusedWorkspace == "2")
        #expect(effects.isEmpty)
    }

    @Test("a load drops windows AeroSpace no longer lists")
    func loadedRemovesStale() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"), window(2, "B"))], focusedWorkspace: "1")
        let result = OverviewResult(workspaces: [ws("1", window(1, "A"))], focus: Focus(workspace: "1"))

        let (new, effects) = updateOverview(s, .loaded(result))

        #expect(windowIds(new, workspace: "1") == [1])
        #expect(effects.contains(.windowRemoved(2)))
    }

    @Test("a load whose focus reads did not answer leaves focus alone")
    func loadedWithoutFocusKeepsIt() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"))], focusedWindowId: 1, focusedWorkspace: "1")
        let (new, _) = updateOverview(s, .loaded(OverviewResult(workspaces: [ws("1", window(1, "A"))])))

        #expect(new.focusedWindowId == 1)
        #expect(new.focusedWorkspace == "1")
    }

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

    /// Events carry no data: AeroSpace is silent about close, quit, quiet moves and every
    /// layout change, so a reload is mandatory whatever an event might have said.
    @Test("an event that means something reloads and changes nothing itself")
    func eventsOnlyRefresh() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"))], focusedWindowId: 1, focusedWorkspace: "1")
        let (new, effects) = updateOverview(s, .event(.changed))
        #expect(new == s)
        #expect(effects == [.refresh])
    }

    @Test("an event that moves no window does nothing at all")
    func inertEvent() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"))], focusedWorkspace: "1")
        let (new, effects) = updateOverview(s, .event(.other))
        #expect(new == s)
        #expect(effects.isEmpty)
    }
}

@Suite("update — action")
struct ActionTests {

    /// Every action but a merge is forwarded untouched: AeroSpace is the source of truth,
    /// so the model changes only when a load says it did.
    @Test("actions run their command and leave the model alone", arguments: [
        AeroControlAction.focusWorkspace("2"),
        .focusWindow(1),
        .closeWindow(1),
        .closeWindow(999),                                       // an id the model does not hold
        .moveWindow(windowId: 1, toWorkspace: "2"),
        .moveWindowQuietly(windowId: 1, toWorkspace: "2"),
    ])
    func actionsAreForwarded(action: AeroControlAction) {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A")), ws("2")],
                              focusedWindowId: 1, focusedWorkspace: "1")
        let (new, effects) = updateOverview(s, .action(action))
        #expect(new == s)
        #expect(effects == [.runAction(action)])
    }
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
