import AppKit
import Observation
import Testing
@testable import AeroControlKit
@testable import Common

// MARK: - Fake ports

/// Scriptable stand-in for the aerospace CLI. `run` returns the currently-programmed
/// list JSON; `subscribe` exposes a continuation so a test can push raw event lines.
@MainActor
@Suite("OverviewStore")
struct OverviewStoreTests {

    @Test("closing a window runs the command and the reload drops the tile")
    func closeReloadsAndRemovesTile() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(100, "1"), (200, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        // The window is really closed: AeroSpace no longer lists it. The close action runs
        // the CLI command, then reloads — mirroring AeroSpace, which is the source of truth.
        runner.setState(windows: windowsJSON([(200, "1")]), workspaces: workspacesJSON(["1"]))
        await store.dispatch(.closeWindow(100))

        await waitUntil { windowIds(store) == [200] }
        #expect(windowIds(store) == [200])
    }

    @Test("a refresh event reloads and applies the latest state")
    func refreshAppliesFetchedState() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        await waitUntil { runner.isSubscribed }
        runner.sendEvent("{\"_event\":\"binding-triggered\"}")

        await waitUntil { windowIds(store).contains(2) }
        #expect(windowIds(store) == [1, 2])
    }

    @Test("a reload mirrors AeroSpace verbatim — a window it no longer lists disappears")
    func reloadMirrorsAerospace() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        #expect(windowIds(store) == [1, 2])

        // AeroSpace dropped window 2; the next event-driven reload reflects that exactly —
        // no CGWindowList cross-check, no suppression. AeroSpace is the source of truth.
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        await waitUntil { runner.isSubscribed }
        runner.sendEvent("{\"_event\":\"binding-triggered\"}")

        await waitUntil { windowIds(store) == [1] }
        #expect(windowIds(store) == [1])
    }

    @Test("a same-monitor content change invalidates the observable model; a no-op reload does not")
    func contentChangeInvalidatesModel() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        // Count how many times the @Observable model would invalidate SwiftUI. This is the
        // real render trigger now that the hosted NSHostingView auto-observes `model`
        // (the manual diff/rebuild layer is gone).
        let invalidations = await ModelInvalidationCounter(store)
        try? await Task.sleep(for: .milliseconds(20))
        let before = await invalidations.count

        // Window 1 moves from ws "1" to ws "2" on the same monitor: AeroSpace now lists it
        // under "2" and emits a workspace-changed event that drives a reconcile. The panel
        // auto-observes, so the store just assigns the new model — a real change.
        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        await waitUntil { runner.isSubscribed }
        runner.sendEvent("{\"_event\":\"focused-workspace-changed\",\"workspace\":\"2\",\"prevWorkspace\":\"1\"}")

        await waitUntil { workspaceOf(store, 1) == "2" }
        #expect(workspaceOf(store, 1) == "2")
        #expect(await invalidations.count > before)

        // A reload that returns identical state must not reassign `model`, so no-op
        // reconciles never re-render the panel (avoids flashing / mid-hover resets).
        let afterChange = await invalidations.count
        runner.sendEvent("{\"_event\":\"binding-triggered\"}")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await invalidations.count == afterChange)
    }

    @Test("a burst of reloads to the same state invalidates the model at most once")
    func rapidRefreshesRenderOnce() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        let invalidations = await ModelInvalidationCounter(store)
        try? await Task.sleep(for: .milliseconds(20))
        let before = await invalidations.count

        // AeroSpace now reports window 1 on ws "2". Fire a burst of refresh-driving events:
        // every reload re-reads the SAME new state, so only the first apply differs from the
        // model. Mirroring AeroSpace on every event must not stress the UI — the model is
        // assigned exactly once for the burst, and no-op reloads never reassign it.
        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        await waitUntil { runner.isSubscribed }
        for _ in 0..<5 {
            runner.sendEvent("{\"_event\":\"binding-triggered\"}")
        }

        await waitUntil { workspaceOf(store, 1) == "2" }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(workspaceOf(store, 1) == "2")
        let delta = await invalidations.count - before
        #expect(delta == 1, "burst to one new state must render once, got \(delta)")
    }
}
