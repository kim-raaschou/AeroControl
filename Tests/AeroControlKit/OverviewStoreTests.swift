import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// The overview is a one shot. It reads AeroSpace's whole state when it is summoned, follows
// the event stream only while it is on screen, and keeps nothing in sync while hidden. These
// drive the store through its one entrance (`send`) and its one reading (`reload`).

@MainActor
@Suite("OverviewStore")
struct OverviewStoreTests {

    private func started(_ runner: ScriptRunner, _ bridge: FakeBridge = FakeBridge()) -> OverviewStore {
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.start()
        return store
    }

    @Test("a reload mirrors AeroSpace verbatim, focus included")
    func reloadMirrorsAerospace() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1", "2"]))
        runner.setFocus(windowId: 2, workspace: "1")
        let store = started(runner)

        await store.reload()
        #expect(windowIds(store) == [1, 2])
        #expect(store.model.focusedWindowId == 2)
        #expect(store.model.focusedWorkspace == "1")
        #expect(store.error == nil)

        // A window AeroSpace no longer lists disappears on the next reading.
        runner.setState(windows: windowsJSON([(2, "1")]), workspaces: workspacesJSON(["1", "2"]))
        await store.reload()
        #expect(windowIds(store) == [2])
        store.stop()
    }

    @Test("a focused workspace with no windows still focuses the workspace")
    func emptyWorkspaceCanBeFocused() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "4"]))
        runner.setFocus(windowId: nil, workspace: "4")
        let store = started(runner)

        await store.reload()
        #expect(store.model.focusedWorkspace == "4")
        #expect(store.model.focusedWindowId == 0)
        store.stop()
    }

    @Test("a load asks AeroSpace for the lists and for what is focused")
    func loadReadsFocus() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()

        #expect(runner.commandsRun.contains { $0.first == "list-windows" && $0.contains("--all") })
        #expect(runner.commandsRun.contains { $0.first == "list-windows" && $0.contains("--focused") })
        #expect(runner.commandsRun.contains { $0.first == "list-workspaces" && $0.contains("--focused") })
        store.stop()
    }

    @Test("a load AeroSpace refuses leaves a readable error, and the next one clears it")
    func failedLoadSetsError() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)

        runner.failing = true
        await store.reload()
        #expect(store.error?.contains("no aerospace") == true)

        runner.failing = false
        await store.reload()
        #expect(store.error == nil)
        #expect(windowIds(store) == [1])
        store.stop()
    }

    @Test("a load whose focus reads fail leaves the focus it already had")
    func failedFocusReadKeepsFocus() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        runner.setFocus(windowId: 1, workspace: "1")
        let store = started(runner)
        await store.reload()
        #expect(store.model.focusedWorkspace == "1")

        // AeroSpace answers the lists but not the focus reads: focus must not be wiped.
        runner.refuseFocusReads = true
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        await store.reload()
        #expect(windowIds(store) == [1, 2])
        #expect(store.model.focusedWindowId == 1)
        #expect(store.model.focusedWorkspace == "1")
        store.stop()
    }

    // MARK: Following AeroSpace, only while on screen

    @Test("the subscription is scoped to visibility")
    func followingIsScopedToVisibility() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        #expect(!runner.isSubscribed)             // hidden: nothing to stay in sync with

        store.startFollowingAerospace()
        await waitUntil { runner.isSubscribed }
        #expect(runner.isSubscribed)

        store.stopFollowingAerospace()
        await waitUntil { !runner.isSubscribed }
        #expect(!runner.isSubscribed)
        store.stop()
    }

    @Test("while following, an event reconciles against AeroSpace")
    func eventReconciles() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()
        store.startFollowingAerospace()
        await waitUntil { runner.isSubscribed }

        // The event says nothing; the reload says everything.
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent(#"{"_event":"focus-changed","windowId":1,"workspace":"1"}"#)
        await waitUntil { windowIds(store) == [1] }
        #expect(windowIds(store) == [1])
        store.stop()
    }

    @Test("an event that moves no window neither changes the model nor reloads")
    func inertEventIsInert() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()
        store.startFollowingAerospace()
        await waitUntil { runner.isSubscribed }
        let before = runner.commandsRun.count

        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent(#"{"_event":"mode-changed","mode":"resize"}"#)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(windowIds(store) == [1])
        #expect(runner.commandsRun.count == before)
        store.stop()
    }

    // MARK: The typed filter

    /// `count` windows of one app, one of which carries a title no other holds.
    private func teams(_ count: Int) -> String {
        "[" + (1...count).map { oneWindow($0, "1", app: "Teams", title: $0 == 1 ? "Crew standup" : nil) }
            .joined(separator: ",") + "]"
    }

    @Test("a wide query still draws every match: the grid sizes them, so there is no cut-off")
    func wideQueryKeepsEveryMatch() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(12), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()

        store.filter = "Teams"
        #expect(store.filterMatches.count == 12)
        #expect(filterOrdinals(matches: store.filterMatches).count == 9)   // only nine digits

        store.filter = "standup"
        #expect(store.filterMatches.map(\.window.windowId) == [1])
        store.stop()
    }

    @Test("the filter is the user's alone: no reload touches it, and it asks AeroSpace nothing")
    func filterIsIndependentOfTheReducer() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(2), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()

        store.filter = "standup"
        let commands = runner.commandsRun.count

        // A window appears while the query stands: the query survives, the matches re-derive.
        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        await store.reload()
        #expect(store.filter == "standup")
        #expect(store.filterMatches.map(\.window.windowId) == [1])

        store.filter = "Teams"
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.filterMatches.count == 3)
        #expect(runner.commandsRun.count == commands + 4)   // the reload's four reads, nothing else
        store.stop()
    }

    // MARK: Actions

    @Test("typed inputs drive the store through the send() ingress")
    func typedInputsDriveStore() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)

        store.send(.loaded(result([("1", [1, 2])])))
        await waitUntil { windowIds(store) == [1, 2] }
        #expect(windowIds(store) == [1, 2])

        // An action shares the same ingress: it runs the CLI, then reconciles against
        // reality. AeroSpace now lists nothing, so the tile drops.
        runner.setState(windows: "[]", workspaces: workspacesJSON(["1"]))
        store.send(.action(.closeWindow(1)))
        await waitUntil { windowIds(store).isEmpty }
        #expect(runner.didRun(["close", "--window-id", "1"]))
        #expect(windowIds(store).isEmpty)
        store.stop()
    }

    @Test("focus actions run their command and leave the model alone", arguments: [
        (AeroControlAction.focusWorkspace("2"), ["workspace", "2"]),
        (AeroControlAction.focusWindow(5), ["focus", "--window-id", "5"]),
    ])
    func focusActionsRunCommandOnly(action: AeroControlAction, argv: [String]) async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = started(runner)
        await store.reload()
        let before = windowIds(store)

        store.send(.action(action))
        await waitUntil { runner.didRun(argv) }
        #expect(runner.didRun(argv))
        // The overview dismisses on a focus action; there is nothing left to reconcile.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(windowIds(store) == before)
        store.stop()
    }

    @Test("moveWindow runs its command and reconciles the tile to its new workspace")
    func moveWindowReconciles() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = started(runner)
        await store.reload()
        #expect(workspaceOf(store, 1) == "1")

        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        store.send(.action(.moveWindow(windowId: 1, toWorkspace: "2")))
        await waitUntil { runner.didRun(["move-node-to-workspace", "--window-id", "1", "--focus-follows-window", "2"]) }
        await waitUntil { workspaceOf(store, 1) == "2" }
        #expect(workspaceOf(store, 1) == "2")
        store.stop()
    }

    @Test("a burst of actions collapses to the latest reality")
    func burstReconcilesToLatest() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1"), (3, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()
        #expect(windowIds(store) == [1, 2, 3])

        // Every reconcile re-reads the SAME latest reality, so the newest-wins generation
        // stamp collapses the burst to the final state.
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        store.send(.action(.closeWindow(2)))
        store.send(.action(.closeWindow(3)))

        await waitUntil { windowIds(store) == [1] }
        #expect(windowIds(store) == [1])
        store.stop()
    }

    @Test("a content change invalidates the observable model; a no-op reload does not")
    func contentChangeInvalidatesModel() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = started(runner)
        await store.reload()

        let invalidations = ModelInvalidationCounter(store)
        try? await Task.sleep(for: .milliseconds(20))
        let before = invalidations.count

        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        await store.reload()
        await waitUntil { workspaceOf(store, 1) == "2" }
        await waitUntil { invalidations.count > before }
        #expect(invalidations.count > before)

        // A reload that returns identical state must not reassign `model`, so no-op
        // readings never re-render the panel (avoids flashing / mid-hover resets).
        let afterChange = invalidations.count
        await store.reload()
        await store.reload()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(invalidations.count == afterChange)
        store.stop()
    }
}

@MainActor
@Suite("OverviewStore — previews")
struct OverviewStorePreviewTests {

    @Test("capturePreviews asks the bridge for exactly the model's windows and stores them")
    func capturesModelWindows() async {
        let runner = ScriptRunner(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.granted = true
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.start()
        await store.reload()

        #expect(store.previewsAvailable)
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        #expect(bridge.captured == [[1, 2]])
        #expect(store.previews.count == 2)

        store.clearPreviews()
        #expect(store.previews.isEmpty)
        store.stop()
    }

    @Test("without Screen Recording the store reports previews unavailable and asks on request")
    func permission() async {
        let runner = ScriptRunner(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.start()

        #expect(!store.previewsAvailable)
        store.requestPreviewAccess()
        #expect(bridge.accessRequests == 1)
        await store.capturePreviews(maxSize: CGSize(width: 10, height: 10))
        #expect(store.previews.isEmpty)
        store.stop()
    }
}
