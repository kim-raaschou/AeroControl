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

    @Test("loaded erstatter workspaces, focus uændret (events er SOT)")
    func loadedBasic() {
        let s = OverviewModel(workspaces: [], focusedWindowId: 0, focusedWorkspace: "")
        let result = OverviewResult(workspaces: [
            ws("1", window(603, "Warp"), window(10159, "Arc")),
            ws("2", window(9009, "IDEA")),
        ])

        let (new, effects) = updateOverview(s, .loaded(result))

        #expect(new.workspaces.count == 2)
        // Focus NOT set from result — events are SOT
        #expect(new.focusedWorkspace == "")
        #expect(windowIds(new, workspace: "1") == [603, 10159])
        #expect(windowIds(new, workspace: "2") == [9009])
        #expect(effects.contains(.loadIcons(new.workspaces.flatMap(\.windows))))
    }

    @Test("loaded fyrer windowRemoved for forsvundne vinduer")
    func loadedRemovesStale() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"), window(2, "B"))], focusedWorkspace: "1")
        let result = OverviewResult(workspaces: [
            ws("1", window(1, "A")),
        ])

        let (new, effects) = updateOverview(s, .loaded(result))

        #expect(windowIds(new, workspace: "1") == [1])
        #expect(effects.contains(.windowRemoved(2)))
    }

    @Test("loaded ændrer aldrig focusedWorkspace")
    func loadedPreservesFocus() {
        let s = OverviewModel(focusedWorkspace: "1")
        let result = OverviewResult(workspaces: [])

        let (new, _) = updateOverview(s, .loaded(result))

        #expect(new.focusedWorkspace == "1")
    }
}

@Suite("update — focus-changed")
struct FocusChangedTests {

    @Test("fokus-skifte inden for workspace")
    func focusSameWorkspace() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"), window(10159, "Arc"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(.focusChanged(windowId: 10159, workspace: "1")))

        #expect(new.focusedWindowId == 10159)
        #expect(new.focusedWorkspace == "1")
        #expect(windowIds(new, workspace: "1") == [603, 10159])
        #expect(effects == [.refresh])
    }

    @Test("fokus-skifte bevarer vindue-rækkefølge")
    func focusPreservesOrder() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"), window(2, "B"), window(3, "C"))], focusedWorkspace: "1")

        let (new, _) = updateOverview(s, .event(.focusChanged(windowId: 3, workspace: "1")))

        #expect(windowIds(new, workspace: "1") == [1, 2, 3])
    }

    @Test("fokus til tomt workspace: windowId nil")
    func focusEmpty() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(.focusChanged(windowId: nil, workspace: "5")))

        #expect(new.focusedWindowId == 0)
        #expect(new.focusedWorkspace == "5")
        #expect(effects == [.refresh])
    }

    @Test("fokus-change rører ikke modellen, kun focus + refresh")
    func focusDoesNotMoveWindow() {
        let s = OverviewModel(workspaces: [
            ws("1", window(603, "Warp"), window(10159, "Arc")),
            ws("2", window(9009, "IDEA"))
        ], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(.focusChanged(windowId: 10159, workspace: "2")))

        #expect(new.focusedWindowId == 10159)
        #expect(new.focusedWorkspace == "2")
        // Events are source-of-truth via reload: no optimistic move
        #expect(windowIds(new, workspace: "1") == [603, 10159])
        #expect(windowIds(new, workspace: "2") == [9009])
        #expect(effects == [.refresh])
    }

    @Test("fokus-change til ukendt workspace opretter ikke workspace")
    func focusDoesNotCreateWorkspace() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(.focusChanged(windowId: 603, workspace: "7")))

        #expect(new.focusedWorkspace == "7")
        #expect(windowIds(new, workspace: "1") == [603])
        #expect(new.workspaces.map(\.name) == ["1"])
        #expect(effects == [.refresh])
    }
}

@Suite("update — workspace-changed / monitor-changed")
struct WorkspaceChangedTests {

    @Test("workspace-changed opdaterer focusedWorkspace")
    func workspaceChanged() {
        let s = OverviewModel(workspaces: [ws("1"), ws("2")], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(.workspaceChanged(workspace: "2", prevWorkspace: "1")))

        #expect(new.focusedWorkspace == "2")
        #expect(effects == [.refresh])
    }

    @Test("monitor-changed opdaterer focusedWorkspace")
    func monitorChanged() {
        let s = OverviewModel(workspaces: [ws("1"), ws("2")], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(.monitorChanged(workspace: "2", monitorId: nil)))

        #expect(new.focusedWorkspace == "2")
        #expect(effects == [.refresh])
    }
}

@Suite("update — window-detected")
struct WindowDetectedTests {

    @Test("window-detected rører ikke modellen, kun refresh")
    func detectedDoesNotMutate() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(
            .windowDetected(windowId: 999, workspace: "1", appBundleId: "com.jetbrains", appName: "IDEA")
        ))

        #expect(new == s)
        #expect(effects == [.refresh])
    }

    @Test("window-detected på ukendt workspace opretter ikke workspace")
    func detectedDoesNotCreateWorkspace() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(
            .windowDetected(windowId: 999, workspace: "3", appBundleId: nil, appName: "Safari")
        ))

        #expect(new == s)
        #expect(new.workspaces.map(\.name) == ["1"])
        #expect(effects == [.refresh])
    }

    @Test("window-detected med nil workspace er no-op")
    func detectedNilWorkspace() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(
            .windowDetected(windowId: 999, workspace: nil, appBundleId: nil, appName: nil)
        ))

        #expect(new == s)
        #expect(effects == [.refresh])
    }

    @Test("window-detected ændrer ikke fokus")
    func detectedDoesNotChangeFocus() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))],
                         focusedWindowId: 603, focusedWorkspace: "1")

        let (new, _) = updateOverview(s, .event(
            .windowDetected(windowId: 999, workspace: "2", appBundleId: nil, appName: "IDEA")
        ))

        #expect(new.focusedWindowId == 603)
        #expect(new.focusedWorkspace == "1")
    }
}

@Suite("update — windowsValidated")
struct ValidationTests {

    @Test("fjerner stale vinduer")
    func removesStale() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"), window(2, "B"), window(3, "C"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .windowsValidated(liveIds: [1, 3]))

        #expect(windowIds(new, workspace: "1") == [1, 3])
        #expect(effects.contains(.windowRemoved(2)))
    }

    @Test("alle vinduer fra termineret app fjernes")
    func removesAllFromApp() {
        let s = OverviewModel(workspaces: [ws("1", window(100, "Safari"), window(200, "Safari"), window(603, "Warp"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .windowsValidated(liveIds: [603]))

        #expect(windowIds(new, workspace: "1") == [603])
        #expect(effects.contains(.windowRemoved(100)))
        #expect(effects.contains(.windowRemoved(200)))
    }

    @Test("ingen stale vinduer er no-op")
    func noStaleIsNoop() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"), window(2, "B"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .windowsValidated(liveIds: [1, 2]))

        #expect(new == s)
        #expect(effects == [])
    }

    @Test("tom liveIds er no-op")
    func emptyLiveIdsIsNoop() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .windowsValidated(liveIds: []))

        #expect(new == s)
        #expect(effects == [])
    }

    @Test("workspace tømmes men eksisterer stadig")
    func workspaceEmptied() {
        let s = OverviewModel(workspaces: [
            ws("1", window(603, "Warp")),
            ws("2", window(9009, "IDEA"))
        ], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .windowsValidated(liveIds: [603]))

        #expect(windowIds(new, workspace: "2") == [])
        #expect(windowIds(new, workspace: "1") == [603])
        #expect(effects.contains(.windowRemoved(9009)))
    }
}

struct OtherTests {

    @Test("other event er no-op")
    func otherIsNoop() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(.other))

        #expect(new == s)
        #expect(effects == [])
    }
}


@Suite("update — sammensatte scenarier")
struct CompositeTests {

    @Test("åbn ny app: detected + focus-changed opdaterer kun focus + refresh")
    func openNewApp() {
        var s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))], focusedWorkspace: "1")

        let (s1, e1) = updateOverview(s, .event(
            .windowDetected(windowId: 500, workspace: "1", appBundleId: "com.apple.Safari", appName: "Safari")
        ))
        s = s1

        let (s2, _) = updateOverview(s, .event(.focusChanged(windowId: 500, workspace: "1")))
        s = s2

        // Events don't mutate the model — the reload is source-of-truth
        #expect(windowIds(s, workspace: "1") == [603])
        #expect(s.focusedWindowId == 500)
        #expect(e1 == [.refresh])
    }

    @Test("detected på ws2, focus-changed til ws1 rører ikke vinduerne")
    func detectedThenFocusNoMove() {
        var s = OverviewModel(workspaces: [
            ws("1", window(603, "Warp")),
            ws("2", window(38, "Finder"))
        ], focusedWorkspace: "1")

        let (s1, _) = updateOverview(s, .event(
            .windowDetected(windowId: 999, workspace: "2", appBundleId: nil, appName: "IDEA")
        ))
        s = s1
        #expect(windowIds(s, workspace: "2") == [38])

        let (s2, e2) = updateOverview(s, .event(.focusChanged(windowId: 999, workspace: "1")))
        s = s2

        // Only focus fields change; window placement waits for the reload
        #expect(s.focusedWindowId == 999)
        #expect(s.focusedWorkspace == "1")
        #expect(windowIds(s, workspace: "2") == [38])
        #expect(windowIds(s, workspace: "1") == [603])
        #expect(e2 == [.refresh])
    }

    @Test("workspace-switch: workspace-changed + focus-changed")
    func workspaceSwitch() {
        var s = OverviewModel(workspaces: [
            ws("1", window(603, "Warp")),
            ws("2", window(9009, "IDEA"))
        ], focusedWorkspace: "1")

        let (s1, _) = updateOverview(s, .event(.workspaceChanged(workspace: "2", prevWorkspace: "1")))
        s = s1

        let (s2, _) = updateOverview(s, .event(.focusChanged(windowId: 9009, workspace: "2")))
        s = s2

        #expect(s.focusedWindowId == 9009)
        #expect(s.focusedWorkspace == "2")
        #expect(windowIds(s, workspace: "1") == [603])
        #expect(windowIds(s, workspace: "2") == [9009])
    }
}

@Suite("update — duplicate detection")
struct DuplicateDetectionTests {

    @Test("windowDetected med eksisterende windowId i samme workspace er no-op")
    func duplicateInSameWorkspace() {
        let s = OverviewModel(workspaces: [ws("1", window(603, "Warp"))], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(
            .windowDetected(windowId: 603, workspace: "1", appBundleId: nil, appName: "Warp")
        ))

        #expect(windowIds(new, workspace: "1") == [603])
        #expect(effects == [.refresh])
    }

    @Test("windowDetected på tværs af workspaces rører ikke modellen")
    func duplicateAcrossWorkspaceIsRefreshOnly() {
        let s = OverviewModel(workspaces: [
            ws("1", window(603, "Warp")),
            ws("2", window(999, "Safari"))
        ], focusedWorkspace: "1")

        let (new, effects) = updateOverview(s, .event(
            .windowDetected(windowId: 999, workspace: "1", appBundleId: nil, appName: "Safari")
        ))

        #expect(new == s)
        #expect(effects == [.refresh])
    }
}

@Suite("update — move preservation")
struct MovePreservationTests {

    @Test("moveWindow-action bevarer floating metadata")
    func movePreservesFloating() {
        let floatingWindow = WindowInfo(
            windowId: 100, appName: "Warp", bundleId: "com.warp",
            isFloating: true
        )
        let s = OverviewModel(
            workspaces: [
                WorkspaceInfo(name: "1", windows: [floatingWindow]),
                WorkspaceInfo(name: "2", windows: [])
            ],
            focusedWindowId: 100, focusedWorkspace: "1"
        )

        let (new, _) = updateOverview(s, .action(.moveWindow(windowId: 100, toWorkspace: "2")))

        let movedWindow = new.workspaces.first(where: { $0.name == "2" })?.windows.first
        #expect(movedWindow?.isFloating == true)
    }
}


@Suite("update — action")
struct ActionTests {

    @Test("focusWorkspace kører CLI uden model-ændring")
    func focusWorkspaceRunsAction() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"))], focusedWorkspace: "1")
        let (new, effects) = updateOverview(s, .action(.focusWorkspace("2")))
        #expect(new == s)
        #expect(effects == [.runAction(.focusWorkspace("2"))])
    }

    @Test("focusWindow kører CLI uden model-ændring")
    func focusWindowRunsAction() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"))], focusedWorkspace: "1")
        let (new, effects) = updateOverview(s, .action(.focusWindow(1)))
        #expect(new == s)
        #expect(effects == [.runAction(.focusWindow(1))])
    }

    @Test("closeWindow fjerner tile optimistisk og kører CLI")
    func closeWindowRunsAction() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"))], focusedWorkspace: "1")
        let (new, effects) = updateOverview(s, .action(.closeWindow(1)))
        // The tile is removed immediately so the close feels instant; the interpreter
        // reconciles against reality afterwards.
        #expect(new.workspaces.first?.windows.isEmpty == true)
        #expect(effects == [.windowRemoved(1), .runAction(.closeWindow(1))])
    }

    @Test("closeWindow på ukendt window-id rører ikke modellen")
    func closeUnknownWindowIsNoOp() {
        let s = OverviewModel(workspaces: [ws("1", window(1, "A"))], focusedWorkspace: "1")
        let (new, effects) = updateOverview(s, .action(.closeWindow(999)))
        #expect(new == s)
        #expect(effects == [.runAction(.closeWindow(999))])
    }

    @Test("moveWindow flytter optimistisk i model og opdaterer focus + kører CLI")
    func moveWindowOptimistic() {
        let s = OverviewModel(
            workspaces: [ws("1", window(1, "A"), window(2, "B")), ws("2")],
            focusedWindowId: 1, focusedWorkspace: "1"
        )
        let (new, effects) = updateOverview(s, .action(.moveWindow(windowId: 1, toWorkspace: "2")))

        #expect(windowIds(new, workspace: "1") == [2])
        #expect(windowIds(new, workspace: "2") == [1])
        #expect(new.focusedWorkspace == "2")
        #expect(effects == [.runAction(.moveWindow(windowId: 1, toWorkspace: "2"))])
    }

    @Test("moveWindow til ny workspace opretter den og arver monitor")
    func moveWindowToNewWorkspace() {
        let s = OverviewModel(
            workspaces: [WorkspaceInfo(name: "1", windows: [window(1, "A")], monitorId: 3)],
            focusedWorkspace: "1"
        )
        let (new, effects) = updateOverview(s, .action(.moveWindow(windowId: 1, toWorkspace: "9")))

        #expect(windowIds(new, workspace: "1") == [])
        #expect(windowIds(new, workspace: "9") == [1])
        #expect(new.workspaces.first(where: { $0.name == "9" })?.monitorId == 3)
        #expect(new.focusedWorkspace == "9")
        #expect(effects == [.runAction(.moveWindow(windowId: 1, toWorkspace: "9"))])
    }
}
