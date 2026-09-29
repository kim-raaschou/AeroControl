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

    @Test("the filter is the user's alone: no reload touches it, and it asks AeroSpace nothing")
    func filterIsIndependentOfTheReducer() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(2), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()

        store.filter = "standup"

        // A window appears while the query stands: the query survives, the matches re-derive.
        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        await store.reload()
        #expect(store.filter == "standup")
        #expect(store.filterMatches.map(\.window.windowId) == [1])

        // Changing the query is a local matter: it asks AeroSpace nothing.
        let commands = runner.commandsRun.count
        store.filter = "Teams"
        #expect(store.filterMatches.count == 3)
        #expect(runner.commandsRun.count == commands)
        store.stop()
    }

    @Test("keys go through the store: text narrows, Tab walks the ring, Enter hands back a pick")
    func keysGoThroughTheStore() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(2), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()

        #expect(store.handle(.character("T")) == .setQuery("T"))
        store.filter = "Teams"
        let second = store.filterMatches[1].window.windowId
        #expect(store.handle(.next) == .select(1) && store.ringWindowId == second)
        #expect(store.handle(.enter) == .focus(windowId: second))
        store.tileRows["1"] = [[1], [2]]                                         // what the card reports as it lays out
        #expect(store.handle(.down) == .select(0))                               // one column, from the last: round to the first
        // A keystroke puts the ring back on the first match: the list under it changed.
        #expect(store.handle(.character("x")) == .setQuery("Teamsx") && store.selection == nil)
        #expect(store.handle(.escape) == .setQuery("") && store.ringWindowId == store.model.focusedWindowId)
        store.stop()
    }

    @Test("the map is navigable too: the ring rests on the focused window, and the same keys move it and pick")
    func mapNavigation() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        runner.setFocus(windowId: 2, workspace: "1")
        let store = started(runner)
        await store.reload()

        #expect(store.selection == nil && store.ringWindowId == 2)
        #expect(store.handle(.next) == .select(2) && store.ringWindowId == 3)
        #expect(store.handle(.enter) == .focus(windowId: 3))
        #expect(store.handle(.previous) == .select(1) && store.handle(.previous) == .select(0))
        #expect(store.handle(.character("x")) == .setQuery("x") && store.selection == nil)   // typing resets the ring
        store.stop()
    }

    @Test("an app summon decides what one key does: start it, focus a window, or open the picker")
    func appSummon() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        runner.setFocus(windowId: 2, workspace: "1")
        let store = started(runner)
        await store.reload()

        // Three windows and the picker on: the picker, the ring on the one after the focused.
        #expect(store.summonApp(bundleId: "com.app", picker: true) == .pick)     // every fixture window is com.app
        #expect(store.filter == "Teams" && store.ringWindowId == 3)
        store.filter = ""

        // The strip off: its rules are off — no picker, no choosing. The app is brought
        // forward and macOS decides which of its windows is in front.
        #expect(store.summonApp(bundleId: "com.app", picker: false) == .launch)
        #expect(store.filter == "")

        // Not running: start it.
        #expect(store.summonApp(bundleId: "com.nothing", picker: true) == .launch && store.filter == "")

        // One window: focus it.
        runner.setState(windows: windowsJSON([(7, "1")]), workspaces: workspacesJSON(["1"]))
        await store.reload()
        #expect(store.summonApp(bundleId: "com.app", picker: true) == .focus(windowId: 7) && store.filter == "")
        store.stop()
    }

    @Test("two windows toggle when you are in one of them; from anywhere else the picker or the first")
    func twoWindowsToggle() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(2), workspaces: workspacesJSON(["1"]))
        runner.setFocus(windowId: 1, workspace: "1")
        let store = started(runner)
        await store.reload()

        #expect(store.summonApp(bundleId: "com.app", picker: true) == .focus(windowId: 2))   // nothing to pick between
        #expect(store.filter == "")
        runner.setFocus(windowId: 2, workspace: "1")
        await store.reload()
        #expect(store.summonApp(bundleId: "com.app", picker: true) == .focus(windowId: 1))   // and back

        runner.setFocus(windowId: nil, workspace: nil)                            // coming from another app
        await store.reload()
        #expect(store.summonApp(bundleId: "com.app", picker: true) == .pick)
        store.filter = ""

        // The strip off switches the toggle off with it.
        runner.setFocus(windowId: 1, workspace: "1")
        await store.reload()
        #expect(store.summonApp(bundleId: "com.app", picker: false) == .launch)
        store.stop()
    }

    @Test("the focused-app summon is the same rule for the app you are in; with nothing focused, it does nothing")
    func focusedAppSummon() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        runner.setFocus(windowId: 2, workspace: "1")
        let store = started(runner)
        await store.reload()

        #expect(store.summonApp(bundleId: nil, picker: true) == .pick)
        #expect(store.filter == "Teams" && store.ringWindowId == 3)             // the one after the focused
        #expect(store.handle(.enter) == .focus(windowId: 3))

        store.filter = ""
        runner.setState(windows: teams(1), workspaces: workspacesJSON(["1"]))
        runner.setFocus(windowId: 1, workspace: "1")
        await store.reload()
        #expect(store.summonApp(bundleId: nil, picker: true) == .focus(windowId: 1) && store.filter == "")   // one window: already there

        runner.setFocus(windowId: nil, workspace: nil)
        await store.reload()
        #expect(store.summonApp(bundleId: nil, picker: true) == .none)            // nothing focused

        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        runner.setFocus(windowId: 2, workspace: "1")
        await store.reload()
        #expect(store.summonApp(bundleId: nil, picker: false) == .launch && store.filter == "")   // strip off: passes through
        store.stop()
    }

    @Test("apps macOS has hidden are known after a load, so their tiles can be dimmed")
    func hiddenApps() async {
        let runner = ScriptRunner(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.hidden = ["com.app"]
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.start()
        await store.reload()
        #expect(store.hiddenBundleIds == ["com.app"])
        bridge.hidden = []
        await store.reload()
        #expect(store.hiddenBundleIds.isEmpty)
        store.stop()
    }

    @Test("once a query has matches their pictures are re-taken, only theirs, once, and larger")
    func filteredPicturesRefresh() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.granted = true
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.start()
        await store.reload()
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        #expect(bridge.captured == [[1, 2, 3]])

        store.filter = "standup"                                                 // matches window 1 only
        await waitUntil { bridge.captured.count >= 2 }
        #expect(bridge.captured.last == [1])
        #expect(store.previews[1]!.size.width > 100 && store.previews[2]!.size.width == 100)   // sharper, the rest as taken

        try? await Task.sleep(for: .milliseconds(400))
        #expect(bridge.captured.count == 2)                                      // once, not on a clock
        store.filter = ""
        try? await Task.sleep(for: .milliseconds(200))
        #expect(bridge.captured.count == 2)                                      // nothing narrowed: nothing re-taken
        store.stop()
    }

    @Test("a summon that filters before the first picture still gets sharp pictures for its matches")
    func summonWithFilterRefreshesAfterFirstCapture() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.granted = true
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.start()
        await store.reload()
        store.filter = "standup"                                                 // the app summon: filtered before any picture exists
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        await waitUntil { bridge.captured.count >= 2 }
        #expect(bridge.captured.last == [1])
        #expect(store.previews[1]!.size.width > 100)
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
        await store.measurePreviews()
        #expect(store.previewSizes.count == 2)                 // the grid's shape, before any picture
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        #expect(bridge.captured == [[1, 2]])
        #expect(store.previews.count == 2)

        store.clearPreviews()
        #expect(store.previews.isEmpty && store.previewSizes.isEmpty)
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
