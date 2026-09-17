import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// Integration tests for the *single ingress*. After the inbox refactor every live
// driver — the AeroSpace subscribe stream, the native app-termination bridge, and
// user actions — funnels its typed `OverviewInput` into one serialized inbox. These
// tests drive the store across BOTH sources (and directly via `send`) and assert the
// reconciled model, exercising the native-bridge path that the unit suite never touched.

// MARK: - Tests

@MainActor
@Suite("OverviewStore single ingress")
struct StoreIngressIntegrationTests {

    @Test("the native app-termination source reconciles through the one inbox")
    func nativeTerminationSourceReconciles() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(100, "1"), (200, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        await store.start()
        #expect(windowIds(store) == [100, 200])

        // The app owning window 100 quits: AeroSpace no longer lists it. The native bridge
        // funnels `.localWindowClosed` through the same inbox, which reloads and mirrors reality.
        runner.setState(windows: windowsJSON([(200, "1")]), workspaces: workspacesJSON(["1"]))
        await waitUntil { bridge.isListening }
        bridge.terminate()

        await waitUntil { windowIds(store) == [200] }
        #expect(windowIds(store) == [200])
        store.stop()
    }

    @Test("the window-close doorbell reconciles a background close with no focus change")
    func closeDoorbellReconciles() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(100, "1"), (200, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        await store.start()
        #expect(windowIds(store) == [100, 200])

        // A background window closes with the mouse — AeroSpace emits no event. The close
        // doorbell (a global mouse-up) funnels `.localWindowClosed` through the same inbox,
        // which reloads and mirrors reality even though nothing about focus changed.
        runner.setState(windows: windowsJSON([(200, "1")]), workspaces: workspacesJSON(["1"]))
        await waitUntil { bridge.isWatchingCloses }
        bridge.ringCloseDoorbell()

        await waitUntil { windowIds(store) == [200] }
        #expect(windowIds(store) == [200])
        store.stop()
    }

    @Test("both sources funnel through one ordered inbox and each reconciles")
    func bothSourcesShareOneIngress() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1"), (3, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        await store.start()
        #expect(windowIds(store) == [1, 2, 3])
        await waitUntil { runner.isSubscribed && bridge.isListening }

        // Source 1 — an AeroSpace event: window 3 vanished; a focus event drives a reconcile.
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent("{\"_event\":\"focused-workspace-changed\",\"workspace\":\"1\",\"prevWorkspace\":\"1\"}")
        await waitUntil { windowIds(store) == [1, 2] }

        // Source 2 — the native bridge: the app owning window 2 quits.
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        bridge.terminate()
        await waitUntil { windowIds(store) == [1] }

        #expect(windowIds(store) == [1])
        store.stop()
    }

    @Test("typed inputs drive the store directly through the send() ingress")
    func typedInputsDriveStoreThroughOneIngress() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        #expect(windowIds(store) == [1])

        // Script state directly through the one entrance — no CLI, no events.
        store.send(.loaded(result([("1", [1, 2])])))
        await waitUntil { windowIds(store) == [1, 2] }
        #expect(windowIds(store) == [1, 2])

        // A later load mirrors verbatim: a window it no longer lists disappears.
        store.send(.loaded(result([("1", [1])])))
        await waitUntil { windowIds(store) == [1] }
        #expect(windowIds(store) == [1])

        // An action shares the same ingress: it runs the CLI, then reconciles against
        // reality. AeroSpace now lists nothing, so the tile drops.
        runner.setState(windows: "[]", workspaces: workspacesJSON(["1"]))
        store.send(.action(.closeWindow(1)))
        await waitUntil { windowIds(store).isEmpty }
        #expect(windowIds(store).isEmpty)
        store.stop()
    }

    // MARK: Every AeroSpace event type, driven as a real line through parse → subscribe → inbox

    @Test("focus-changed updates the focus fields and reconciles")
    func focusChangedEvent() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        await waitUntil { runner.isSubscribed }

        runner.sendEvent("{\"_event\":\"focus-changed\",\"windowId\":1,\"workspace\":\"2\"}")
        await waitUntil { store.model.focusedWorkspace == "2" }
        #expect(store.model.focusedWindowId == 1)
        #expect(store.model.focusedWorkspace == "2")
        store.stop()
    }

    @Test("focused-workspace-changed sets focus and reloads")
    func workspaceChangedEvent() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        await waitUntil { runner.isSubscribed }

        runner.sendEvent("{\"_event\":\"focused-workspace-changed\",\"workspace\":\"2\",\"prevWorkspace\":\"1\"}")
        await waitUntil { store.model.focusedWorkspace == "2" }
        #expect(store.model.focusedWorkspace == "2")
        store.stop()
    }

    @Test("focused-monitor-changed sets focus and reloads")
    func monitorChangedEvent() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        await waitUntil { runner.isSubscribed }

        runner.sendEvent("{\"_event\":\"focused-monitor-changed\",\"workspace\":\"2\",\"monitorId\":1}")
        await waitUntil { store.model.focusedWorkspace == "2" }
        #expect(store.model.focusedWorkspace == "2")
        store.stop()
    }

    @Test("window-detected reconciles and picks up the new window")
    func windowDetectedEvent() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        #expect(windowIds(store) == [1])
        await waitUntil { runner.isSubscribed }

        runner.setState(windows: windowsJSON([(1, "1"), (9, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent("{\"_event\":\"window-detected\",\"windowId\":9,\"workspace\":\"1\"}")
        await waitUntil { windowIds(store) == [1, 9] }
        #expect(windowIds(store) == [1, 9])
        store.stop()
    }

    @Test("binding-triggered reconciles against reality")
    func bindingTriggeredEvent() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        #expect(windowIds(store) == [1, 2])
        await waitUntil { runner.isSubscribed }

        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent("{\"_event\":\"binding-triggered\"}")
        await waitUntil { windowIds(store) == [1] }
        #expect(windowIds(store) == [1])
        store.stop()
    }

    @Test("an unknown event neither changes the model nor reloads")
    func unknownEventIsInert() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        await waitUntil { runner.isSubscribed }
        let commandsBefore = runner.commandsRun.count

        // Reality changes, but an unrecognized event maps to `.other` — no `.refresh`, so
        // the model must NOT pick up the new state and no CLI reload runs.
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent("{\"_event\":\"totally-unknown\"}")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(windowIds(store) == [1])
        #expect(runner.commandsRun.count == commandsBefore)
        store.stop()
    }

    // MARK: Every user action, driven through the same inbox

    @Test("focusWorkspace runs its CLI command without reloading")
    func focusWorkspaceActionRunsCommandOnly() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        let before = windowIds(store)

        store.send(.action(.focusWorkspace("2")))
        await waitUntil { runner.didRun(["workspace", "2"]) }
        #expect(runner.didRun(["workspace", "2"]))
        // Focus actions don't reconcile — the focus event that follows does.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(windowIds(store) == before)
        store.stop()
    }

    @Test("focusWindow runs its CLI command without reloading")
    func focusWindowActionRunsCommandOnly() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        let before = windowIds(store)

        store.send(.action(.focusWindow(5)))
        await waitUntil { runner.didRun(["focus", "--window-id", "5"]) }
        #expect(runner.didRun(["focus", "--window-id", "5"]))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(windowIds(store) == before)
        store.stop()
    }

    @Test("moveWindow runs its CLI command and reconciles the tile to its new workspace")
    func moveWindowActionRunsAndReconciles() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        #expect(workspaceOf(store, 1) == "1")

        // The move succeeds in reality: AeroSpace now lists window 1 under workspace "2".
        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        store.send(.action(.moveWindow(windowId: 1, toWorkspace: "2")))
        await waitUntil { runner.didRun(["move-node-to-workspace", "--window-id", "1", "--focus-follows-window", "2"]) }
        await waitUntil { workspaceOf(store, 1) == "2" }
        #expect(workspaceOf(store, 1) == "2")
        store.stop()
    }

    // MARK: Ordering across sources

    @Test("a rapid mix of events and actions collapses to the latest reality")
    func burstAcrossSourcesReconcilesToLatest() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1"), (3, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        #expect(windowIds(store) == [1, 2, 3])
        await waitUntil { runner.isSubscribed }

        // Fire a burst from both sources at once; every reconcile re-reads the SAME latest
        // reality, so the newest-wins inbox collapses them to the final state [1].
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        for _ in 0..<4 { runner.sendEvent("{\"_event\":\"binding-triggered\"}") }
        store.send(.action(.closeWindow(2)))
        store.send(.action(.closeWindow(3)))

        await waitUntil { windowIds(store) == [1] }
        #expect(windowIds(store) == [1])
        store.stop()
    }

    // MARK: Output contract — the seam that drives OverlayWindowManager
    //
    // `.loaded` is the store's host-reaction callback that `AeroControlApp` maps to
    // `showErrorFallbackIfNeeded()`. Asserting it here integration-tests *what*
    // OverlayWindowManager is told to do, deterministically and without AppKit.


    @Test("the initial load emits loaded so the host can reveal or show an error")
    func initialLoadEmitsLoaded() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())

        // Attach before `start()` so the one-shot `.loaded` (fired on a later main-queue turn,
        // after the load's icon effects) is captured deterministically.
        let outputs = collect(store)
        await store.start()

        await waitUntil { outputs.count(of: .loaded) >= 1 }
        #expect(outputs.count(of: .loaded) == 1)

        store.stop()
    }
}
