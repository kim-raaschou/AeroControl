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

    @Test("the store remembers whether AeroSpace can give layout rects: unknown while AeroSpace is silent, then learned once")
    func layoutRectsAreLearnedOnce() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        #expect(store.layoutRects == .unknown)

        runner.failing = true
        await store.reload()
        #expect(store.layoutRects == .unknown)                       // nothing answered: nothing learned

        runner.failing = false                                     // an AeroSpace release: no --sort-by
        await store.reload()
        #expect(store.layoutRects == .absent)
        let asked = runner.commandsRun.count
        await store.reload()
        #expect(!runner.commandsRun[asked...].contains { $0.contains { $0.contains("window-layout-rect") } })
        store.stop()
    }

    @Test("an AeroSpace that knows %{window-layout-rect} is read with rects from the first load")
    func layoutRectsPresent() async {
        let runner = ScriptRunner()
        runner.acceptsLayoutRects = true
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()
        #expect(store.layoutRects == .present)
        #expect(runner.didRun(AerospaceCommand.listWindows(layoutRects: true)))
        #expect(!runner.didRun(AerospaceCommand.listWindows()))
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
        #expect(store.strip?.marked == 3 && store.ringWindowId == 3 && store.filter == "")   // the strip has its own state, no query
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
        #expect(store.strip?.marked == 3 && store.ringWindowId == 3)             // the one after the focused
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

    // MARK: The strip

    /// A strip open on three Teams windows, the second focused, plus a Slack window whose title says Teams.
    private func stripOnTeams() async -> (ScriptRunner, OverviewStore) {
        let runner = ScriptRunner()
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams"), oneWindow(2, "2", app: "Teams"),
                                        oneWindow(9, "2", app: "Slack", title: "Teams standup notes", bundleId: "com.slack"),
                                        oneWindow(3, "3", app: "Teams")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2", "3"]))
        runner.setFocus(windowId: 2, workspace: "2")
        let store = started(runner)
        await store.reload()
        store.presentation = .strip
        _ = store.summonApp(bundleId: "com.app", picker: true)
        return (runner, store)
    }

    @Test("the strip holds the app's windows by bundle id, in grid order, not every window whose title names it")
    func stripWindowsByBundleId() async {
        let (_, store) = await stripOnTeams()
        #expect(store.stripWindows.map(\.window.windowId) == [1, 2, 3])
        // The cards are whole workspaces: workspace 2 keeps its Slack window, to be drawn grey behind the app's.
        #expect(store.stripWorkspaces.map(\.name) == ["1", "2", "3"])
        #expect(store.stripWorkspaces[1].windows.map(\.windowId) == [2, 9])
        #expect(store.strip?.origin == 2 && store.strip?.marked == 3)
        store.stop()
    }

    @Test("in the strip Tab steps round, Home and End go to the ends, ⌘ and a digit picks, and typing is no query")
    func stripKeys() async {
        let (_, store) = await stripOnTeams()
        #expect(store.handle(.next) == .handled && store.strip?.marked == 1)          // wraps round
        #expect(store.handle(.previous) == .handled && store.strip?.marked == 3)
        #expect(store.handle(.home) == .handled && store.strip?.marked == 1)
        #expect(store.handle(.end) == .handled && store.strip?.marked == 3)
        #expect(store.handle(.character("x")) == .handled && store.filter == "" && store.strip?.marked == 3)
        #expect(store.handle(.character("2")) == .handled && store.strip?.marked == 3)     // a plain digit is not a key
        #expect(store.handle(.commandDigit(2)) == .focus(windowId: 2))
        #expect(store.handle(.enter) == .focus(windowId: 3))
        #expect(store.handle(.escape) == .none)                                        // the window closes the strip
        store.stop()
    }

    @Test("stepping past the last workspace turns the ring once more the same way; back past the first turns it back")
    func stripTurns() async {
        let (_, store) = await stripOnTeams()                                           // Teams on 1, 2 and 3, marked on 3
        #expect(store.strip?.turns == 0)
        store.stepStrip()                                                                // 3 → 1: on round
        #expect(store.strip?.marked == 1 && store.strip?.turns == 1)
        store.stepStrip()                                                                // 1 → 2: no wrap
        #expect(store.strip?.turns == 1)
        store.stepStrip(-1); store.stepStrip(-1)                                         // 2 → 1 → 3: back round
        #expect(store.strip?.marked == 3 && store.strip?.turns == 0)
        store.stop()
    }

    @Test("the summon key again moves the marking on, as Cmd-` does; pointing marks too")
    func stripStepsOnResummon() async {
        let (_, store) = await stripOnTeams()
        store.stepStrip()
        #expect(store.strip?.marked == 1)
        store.markStrip(2)
        #expect(store.strip?.marked == 2)
        store.markStrip(9)                                                              // not the app's: ignored
        #expect(store.strip?.marked == 2)
        store.stop()
    }

    @Test("only a pointer that moved marks: cards sliding under a still mouse do not take the marking")
    func stillPointerDoesNotMark() async {
        let (_, store) = await stripOnTeams()
        store.notePointer(CGPoint(x: 500, y: 300))                                     // where the mouse rests as the strip opens
        store.pointStrip(1, at: CGPoint(x: 500, y: 300))                               // a card slid under it
        #expect(store.strip?.marked == 3)
        store.pointStrip(1, at: CGPoint(x: 520, y: 300))                               // the hand moved
        #expect(store.strip?.marked == 1)
        _ = store.handle(.next)
        store.pointStrip(1, at: CGPoint(x: 520, y: 300))                               // the row turned under a still hand
        #expect(store.strip?.marked == 2)
        store.stop()
    }

    @Test("keys move the carousel's centre with the marking; the pointer marks but leaves the centre, or the row would slide under a still hand")
    func pointerLeavesTheCentre() async {
        let (_, store) = await stripOnTeams()
        #expect(store.strip?.centre == 3)                                              // opens centred on the marking
        store.markStrip(1)
        #expect(store.strip?.marked == 1 && store.strip?.centre == 3)
        _ = store.handle(.next)
        #expect(store.strip?.marked == 2 && store.strip?.centre == 2)
        _ = store.handle(.home)
        #expect(store.strip?.centre == 1)
        store.stepStrip()
        #expect(store.strip?.centre == 2)
        store.stop()
    }

    @Test("a closed marked window hands the marking to the one that took its place; the map drops the strip")
    func stripKeepsMarkingThroughReload() async {
        let (runner, store) = await stripOnTeams()
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams"), oneWindow(2, "2", app: "Teams")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2", "3"]))
        store.markStrip(3)
        await store.reload()
        #expect(store.strip?.marked == 2)
        store.presentation = .map
        #expect(store.strip == nil)
        store.stop()
    }

    @Test("the strip takes its pictures once: every window of its workspaces, at the strip's size, and nothing else")
    func stripTakesItsPicturesOnce() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        bridge.granted = true
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams"), oneWindow(9, "1", app: "Slack", bundleId: "com.slack"),
                                        oneWindow(2, "2", app: "Teams"), oneWindow(3, "2", app: "Teams"),
                                        oneWindow(7, "3", app: "Slack", bundleId: "com.slack")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2", "3"]))
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.start()
        await store.reload()
        store.presentation = .strip
        _ = store.summonApp(bundleId: "com.app", picker: true)
        await store.capturePreviews(maxSize: CGSize(width: 400, height: 300))
        #expect(bridge.captured == [[1, 9, 2, 3]])                  // Slack on 1 is drawn grey in the card; Slack on 3 is in no card
        #expect(store.previews[9]?.size.width == 400 && store.previews[7] == nil)
        store.stop()
    }

    @Test("the pictures land in the store together, not one by one: held until the capture is in or the reveal is due")
    func picturesLandTogether() async throws {
        let bridge = FakeBridge()
        bridge.granted = true
        bridge.holdAfter = 1
        let store = OverviewStore(runner: ScriptRunner(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"])), nativeSystem: bridge)
        store.start()
        await store.reload()
        let capture = Task { await store.capturePreviews(maxSize: CGSize(width: 100, height: 100)) }
        for _ in 0..<100 where !bridge.isHolding { await Task.yield() }
        #expect(bridge.isHolding && store.previews.isEmpty)                             // one picture in, held back
        try await Task.sleep(for: .milliseconds(250))                                   // past the reveal
        #expect(store.revealsPictures && store.previews.keys.sorted() == [1])
        bridge.release()
        await capture.value
        #expect(store.previews.keys.sorted() == [1, 2])
        store.stop()
    }

    @Test("the pictures are shown together once they are in, and hidden again with them on close")
    func picturesRevealTogether() async {
        let bridge = FakeBridge()
        bridge.granted = true
        let store = OverviewStore(runner: ScriptRunner(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"])), nativeSystem: bridge)
        store.start()
        await store.reload()
        #expect(!store.revealsPictures)
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        #expect(store.revealsPictures)
        store.clearPreviews()
        #expect(!store.revealsPictures)
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

    // MARK: Pictures after a move

    /// A store on screen with its pictures in: summoned, measured, captured.
    private func summoned(_ runner: ScriptRunner, _ bridge: FakeBridge) async -> OverviewStore {
        bridge.granted = true
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.start()
        await store.reload()
        await store.measurePreviews()
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        return store
    }

    @Test("after a move the sizes are measured again and only the windows that changed size get a new picture")
    func moveRetakesOnlyChangedPictures() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1"), (3, "2")]), workspaces: workspacesJSON(["1", "2"]))
        let store = await summoned(runner, bridge)
        #expect(bridge.captured == [[1, 2, 3]])
        let measuredAtSummon = bridge.measured

        // Window 1 goes to workspace 2; window 2 widens into the hole it leaves.
        runner.setState(windows: windowsJSON([(1, "2"), (2, "1"), (3, "2")]), workspaces: workspacesJSON(["1", "2"]))
        bridge.sizes[2] = CGSize(width: 600, height: 200)
        store.send(.action(.moveWindow(windowId: 1, toWorkspace: "2")))
        await waitUntil { bridge.captured.count >= 2 }
        #expect(bridge.measured > measuredAtSummon)
        #expect(bridge.captured.last == [2])
        #expect(store.previewSizes[2] == CGSize(width: 600, height: 200))           // the fresh size, not the summon's
        store.stop()
    }

    @Test("a window that appears while the overview is open gets a picture; nothing changed, nothing is taken")
    func newWindowGetsPictureAndQuietRefreshTakesNone() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = await summoned(runner, bridge)

        runner.setState(windows: windowsJSON([(1, "1"), (4, "1")]), workspaces: workspacesJSON(["1"]))
        store.send(.event(.changed))
        await waitUntil { bridge.captured.count >= 2 }
        #expect(bridge.captured.last == [4])

        let measured = bridge.measured
        store.send(.event(.changed))
        await waitUntil { bridge.measured > measured }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(bridge.captured.count == 2)
        store.stop()
    }

    @Test("a hidden overview takes no pictures on a refresh")
    func hiddenOverviewTakesNone() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = await summoned(runner, bridge)
        store.clearPreviews()
        runner.setState(windows: windowsJSON([(1, "1"), (4, "1")]), workspaces: workspacesJSON(["1"]))
        store.send(.event(.changed))
        await waitUntil { windowIds(store) == [1, 4] }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(bridge.captured.count == 1)
        store.stop()
    }

    @Test("a refresh keeps what the store learned about layout rects instead of asking again")
    func refreshKeepsLayoutRects() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)
        await store.reload()
        #expect(store.layoutRects == .absent)
        let asked = runner.commandsRun.count
        store.send(.event(.changed))
        await waitUntil { runner.commandsRun.count > asked }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(!runner.commandsRun[asked...].contains { $0.contains { $0.contains("window-layout-rect") } })
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
