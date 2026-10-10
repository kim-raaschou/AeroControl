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

    private func picks(_ summon: AppSummon) -> Bool { if case .pick = summon { return true } else { return false } }

    private func started(_ runner: ScriptRunner, _ bridge: FakeBridge = FakeBridge()) -> OverviewStore {
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        store.screen = (available: CGSize(width: 1600, height: 1000), frames: [:])          // the host's screen, as at a summon
        return store
    }

    /// A store read from AeroSpace as the runner has it, the focus where given.
    private func loaded(windows: String, workspaces: String, focus: (Int, String)? = nil) async -> (ScriptRunner, OverviewStore) {
        let runner = ScriptRunner()
        runner.setState(windows: windows, workspaces: workspaces)
        if let focus { runner.setFocus(windowId: focus.0, workspace: focus.1) }
        let store = started(runner)
        await store.reload()
        return (runner, store)
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
    }

    @Test("a load asks AeroSpace for the lists and for what is focused")
    func loadReadsFocus() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))

        #expect(runner.commandsRun.contains { $0.first == "list-windows" && $0.contains("--all") })
        #expect(runner.commandsRun.contains { $0.first == "list-windows" && $0.contains("--focused") })
        #expect(runner.commandsRun.contains { $0.first == "list-workspaces" && $0.contains("--focused") })
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
    }

    @Test("a load whose focus reads fail leaves the focus it already had")
    func failedFocusReadKeepsFocus() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]), focus: (1, "1"))
        #expect(store.model.focusedWorkspace == "1")

        // AeroSpace answers the lists but not the focus reads: focus must not be wiped.
        runner.refuseFocusReads = true
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        await store.reload()
        #expect(windowIds(store) == [1, 2])
        #expect(store.model.focusedWindowId == 1)
        #expect(store.model.focusedWorkspace == "1")
    }

    // MARK: Following AeroSpace, only while on screen

    @Test("one connection to AeroSpace for as long as AeroControl runs: hidden, it only keeps the order of focus; shown, it reads every change")
    func listeningOutlivesVisibility() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        store.startListening()
        await waitUntil { runner.isSubscribed }

        runner.setState(windows: windowsJSON([(1, "1"), (4, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent(#"{"_event":"focus-changed","windowId":4,"workspace":"1"}"#)
        await waitUntil { store.recentWindows.first == 4 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(windowIds(store) == [1])                                                // hidden: nothing read again

        store.following = true
        runner.sendEvent(#"{"_event":"window-detected","windowId":4,"workspace":"1"}"#)
        await waitUntil { windowIds(store) == [1, 4] }
        store.endVisit()
        #expect(runner.isSubscribed)                                                    // still listening
    }

    @Test("while following, an event reconciles against AeroSpace")
    func eventReconciles() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        store.startListening()
        store.following = true
        await waitUntil { runner.isSubscribed }

        // The event says nothing; the reload says everything.
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent(#"{"_event":"focus-changed","windowId":1,"workspace":"1"}"#)
        await waitUntil { windowIds(store) == [1] }
    }

    @Test("an event that moves no window neither changes the model nor reloads")
    func inertEventIsInert() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        store.startListening()
        store.following = true
        await waitUntil { runner.isSubscribed }
        let before = runner.commandsRun.count

        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        runner.sendEvent(#"{"_event":"mode-changed","mode":"resize"}"#)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(windowIds(store) == [1])
        #expect(runner.commandsRun.count == before)
    }

    // MARK: The typed filter

    /// `count` windows of one app, one of which carries a title no other holds.
    private func teams(_ count: Int) -> String {
        "[" + (1...count).map { oneWindow($0, "1", app: "Teams", title: $0 == 1 ? "Crew standup" : nil) }
            .joined(separator: ",") + "]"
    }

    @Test("the store lays the map out itself: a card per workspace shown, a query narrowing them to the ones holding a match; the strip its own cards")
    func laysItselfOut() async {
        let (_, store) = await loaded(windows: windowsJSON([(1, "1"), (2, "1"), (3, "3")]), workspaces: workspacesJSON(["1", "2", "3"]), focus: (2, "1"))
        #expect(store.shown.map(\.name) == ["1", "2", "3"] && !store.filtering && store.cards.map(\.workspace) == ["1", "2", "3"])
        store.filter = "app"                                                            // every window's app
        #expect(store.shown.map(\.name) == ["1", "3"] && store.filtering && store.cards.count == 2 && store.drawn.count == 2)
        store.filter = "zzz"; #expect(store.shown.count == 3 && !store.filtering)       // a miss: the whole map stands
        let (_, strip) = await stripOnTeams()
        #expect(strip.shown.map(\.name) == ["1", "2", "3"] && strip.stripLayout.cards.count == 3 && strip.drawn.count == 3)
    }

    @Test("the filter is the user's alone: no reload touches it, and it asks AeroSpace nothing")
    func filterIsIndependentOfTheReducer() async {
        let (runner, store) = await loaded(windows: teams(2), workspaces: workspacesJSON(["1"]))

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
    }

    @Test("keys go through the store: text narrows, the ring is on the first match, Enter hands back whatever wears the ring")
    func keysGoThroughTheStore() async {
        let (_, store) = await loaded(windows: teams(2), workspaces: workspacesJSON(["1"]), focus: (2, "1"))

        #expect(store.ringWindowId == 2)
        #expect(store.handle(.character("T")) == .setQuery("T"))
        store.filter = "Teams"
        let first = store.filterMatches[0].window.windowId
        #expect(store.ringWindowId == first)
        #expect(store.handle(.enter) == .focus(windowId: first))
        #expect(store.handle(.escape) == .setQuery("") && store.ringWindowId == 2)
        #expect(store.handle(.enter) == .focus(windowId: 2))                          // Enter picks the focused window
    }

    @Test("⌘W and ⌘Q act on the window under the ring: on the map the focused one, or the first match; in the strip the marked one")
    func commandTarget() async {
        let runner = ScriptRunner()
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams"), oneWindow(2, "1", app: "Teams"), oneWindow(3, "1", app: "Teams"),
                                        oneWindow(9, "2", app: "Slack", title: "standup", bundleId: "com.slack")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2"]))
        runner.setFocus(windowId: 2, workspace: "1")
        let store = started(runner)
        await store.reload()
        #expect(store.commandTarget?.windowId == 2)                                     // the ring: AeroSpace's focus
        store.filter = "standup"
        #expect(store.commandTarget?.windowId == 9)                                     // the ring: the first match
        store.filter = ""
        _ = store.summonApp(.bundleId("com.app"))
        #expect(store.strip != nil && store.commandTarget?.windowId == store.strip?.marked)
    }

    @Test("on the map ← and → walk a marking from AeroSpace's focus through a workspace's windows as drawn and on to the next, an empty one a stop where Enter switches to it; AeroSpace moving its focus moves the outline, not the marking; a query starts again")
    func arrowsWalkTheMap() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1"), (2, "1"), (3, "3")]), workspaces: workspacesJSON(["1", "2", "3"]), focus: (2, "1"))
        #expect(store.cards.count == 3 && store.drawn.map { $0.windows.keys.sorted() } == [[1, 2], [-2], [3]])   // as the map lays it out
        #expect(store.handle(.move(.window(1))) == .handled && store.markedWorkspace == "2")    // the empty one
        #expect(store.handle(.move(.window(1))) == .handled && store.ringWindowId == 3)
        #expect(store.handle(.move(.window(1))) == .handled && store.ringWindowId == 1)  // round
        runner.setFocus(windowId: 3, workspace: "3")
        await store.reload()
        #expect(store.model.focusedWindowId == 3 && store.ringWindowId == 1)
        #expect(store.handle(.move(.workspace(1))) == .handled && store.markedWorkspace == "2" && store.handle(.enter) == .handled)
        await waitUntil { runner.didRun(["workspace", "2"]) }
        store.filter = ""; #expect(store.ringWindowId == 3)
    }

    @Test("in the strip ← and → go through the windows as the strip draws them, a card per workspace, round")
    func stripArrowsReadingOrder() async {
        let (_, store) = await stripOnTeams()                                           // Teams 1, 2, 3 on workspaces 1, 2, 3, marked on 3
        #expect(store.drawn.map { $0.windows.keys.sorted() } == [[1], [2], [3]])          // the app's own only: Slack on 2 is no stop
        #expect(store.handle(.move(.window(1))) == .handled && store.strip?.marked == 1 && store.handle(.move(.window(-1))) == .handled
                && store.handle(.move(.window(-1))) == .handled && store.strip?.marked == 2)   // on to 1, back past 3 round to 2
    }

    @Test("⇧⌘ and a workspace's name moves the window under the ring there, on the map and in the strip, and the overview stays up")
    func moveToWorkspace() async {
        let (runner, store) = await loaded(windows: teams(2), workspaces: workspacesJSON(["1", "2"]), focus: (2, "1"))
        #expect(store.handle(.moveToWorkspace("2")) == .handled)
        await waitUntil { runner.didRun(["move-node-to-workspace", "--window-id", "2", "--focus-follows-window", "2"]) }
        let (stripRunner, stripStore) = await stripOnTeams()                              // marked on 3
        #expect(stripStore.handle(.moveToWorkspace("10")) == .handled && stripStore.strip != nil)
        await waitUntil { stripRunner.didRun(["move-node-to-workspace", "--window-id", "3", "--focus-follows-window", "10"]) }
    }

    @Test("pointing at a window on the map moves the ring there, as in the strip; a hover under a hand that has not moved does not")
    func pointingMarksTheMap() async {
        let (_, store) = await loaded(windows: teams(3), workspaces: workspacesJSON(["1"]), focus: (2, "1"))
        store.notePointer(CGPoint(x: 5, y: 5)); store.point(3, at: CGPoint(x: 5, y: 5))
        #expect(store.ringWindowId == 2)                                                // the map opened under a still hand
        store.point(3, at: CGPoint(x: 9, y: 5))
        #expect(store.ringWindowId == 3 && store.model.focusedWindowId == 2)
    }

    @Test("an app summon that opens the strip gives the store its strip, the ring on its marking, and no query (the rule itself: SummonTests)")
    func appSummon() async {
        let (_, store) = await loaded(windows: teams(3), workspaces: workspacesJSON(["1"]), focus: (2, "1"))
        #expect(picks(store.summonApp(.bundleId("com.app"))))
        #expect(store.strip?.marked == 3 && store.ringWindowId == 3 && store.filter == "")
    }

    @Test("an app that would not start is told on the strip's lane: Escape is the window's, every other key does nothing, the next summon or the end of the visit forgets it")
    func missingApp() async {
        let (_, store) = await loaded(windows: teams(3), workspaces: workspacesJSON(["1"]))
        store.missingApp = .bundleId("com.typo")
        #expect(store.handle(.escape) == .none)                                        // the window closes it
        #expect(store.handle(.character("x")) == .handled && store.filter == "")
        #expect(store.handle(.enter) == .handled && store.handle(.commandKey(1)) == .handled)
        _ = store.summonApp(.bundleId("com.app"))
        #expect(store.missingApp == nil && store.strip != nil)
        store.missingApp = .name("Typo")
        store.endVisit()
        #expect(store.missingApp == nil)
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
        _ = store.summonApp(.bundleId("com.app"))
        return (runner, store)
    }

    @Test("the strip holds the app's windows by bundle id, in grid order, not every window whose title names it")
    func stripWindowsByBundleId() async {
        let (_, store) = await stripOnTeams()
        #expect(store.stripWindows.map(\.window.windowId) == [1, 2, 3])
        // The cards are whole workspaces: workspace 2 keeps its Slack window, to be drawn grey behind the app's.
        #expect(store.stripWorkspaces.map(\.name) == ["1", "2", "3"])
        #expect(store.stripWorkspaces[1].windows.map(\.windowId) == [2, 9])
        #expect(store.strip?.marked == 3)
    }

    @Test("in the strip → steps round, a workspace's name goes to it, ⌘ and a window's key picks, and typing is no query")
    func stripKeys() async {
        let (_, store) = await stripOnTeams()
        #expect(store.handle(.move(.window(1))) == .handled && store.strip?.marked == 1)          // wraps round
        #expect(store.handle(.move(.window(-1))) == .handled && store.strip?.marked == 3)
        #expect(store.handle(.character("x")) == .handled && store.filter == "" && store.strip?.marked == 3)
        #expect(store.handle(.character("2")) == .handled && store.strip?.marked == 2)     // workspace 2's first window
        #expect(store.handle(.commandKey(3)) == .focus(windowId: 3) && store.handle(.enter) == .focus(windowId: 2))
        #expect(store.handle(.escape) == .none)                                        // the window closes the strip
    }

    @Test("from another app the strip opens on the app's window that had the focus last")
    func stripOpensOnLastUsed() async {
        let runner = ScriptRunner()
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams"), oneWindow(2, "2", app: "Teams"), oneWindow(3, "3", app: "Teams"),
                                        oneWindow(9, "1", app: "Slack", bundleId: "com.slack")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2", "3"]))
        runner.setFocus(windowId: 9, workspace: "1")                                    // in Slack
        let store = started(runner)
        await store.reload()
        store.noteFocus(2)
        store.noteFocus(9)
        _ = store.summonApp(.bundleId("com.app"))
        #expect(store.strip?.marked == 2)
    }

    @Test("AeroSpace's focus decides while the strip is up: an event that moves no focus, or moves it within the app, leaves it; focus anywhere else ends it, on the event itself")
    func stripEndsWhenFocusLeaves() async {
        let runner = ScriptRunner()
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams"), oneWindow(2, "2", app: "Teams"),
                                        oneWindow(8, "4", app: "Slack", bundleId: "com.slack"), oneWindow(9, "4", app: "Slack", bundleId: "com.slack"),
                                        oneWindow(7, "5", app: "Claude", bundleId: "com.claude")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2", "4", "5"]))
        runner.setFocus(windowId: 7, workspace: "5")                                    // summoned from Claude
        let store = started(runner)
        var done: [Bool] = []
        store.onShotDone = { done.append($0) }
        await store.reload()
        _ = store.summonApp(.bundleId("com.app"))
        store.send(.event(.changed))                                                    // a mode key
        store.send(.event(.focusChanged(windowId: 2, workspace: "2")))                  // into the app
        #expect(store.strip?.app == "com.app" && done.isEmpty)
        store.send(.event(.focusChanged(windowId: 9, workspace: "4")))                  // Slack, of several windows: over all the same
        #expect(store.strip == nil && done == [true])
    }

    @Test("another app's key while a strip is up turns the strip to that app, with the pictures it lacks")
    func stripTakeoverTakesItsPictures() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        bridge.granted = true
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams"), oneWindow(2, "2", app: "Teams"),
                                        oneWindow(8, "3", app: "Slack", bundleId: "com.slack"), oneWindow(9, "4", app: "Slack", bundleId: "com.slack"),
                                        oneWindow(7, "5", app: "Claude", bundleId: "com.claude")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2", "3", "4", "5"]))
        runner.setFocus(windowId: 7, workspace: "5")
        let store = started(runner, bridge)
        await store.reload()
        _ = store.summonApp(.bundleId("com.app"))
        await store.measurePreviews()
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        store.following = true                                                          // the overview is up
        #expect(store.pictures.previews[9] == nil)
        _ = store.summonApp(.bundleId("com.slack"))
        await waitUntil { store.pictures.previews[9] != nil }
        #expect(store.strip?.app == "com.slack" && store.pictures.previews[8] != nil && store.pictures.previews[9] != nil)
    }

    @Test("stepping past the last workspace's window goes on to the first's; back past the first, to the last's")
    func stripWraps() async {
        let (_, store) = await stripOnTeams()                                           // Teams on 1, 2 and 3, marked on 3
        _ = store.handle(.move(.window(1)))                                                                // 3 → 1: on round
        #expect(store.strip?.marked == 1 && store.strip?.centre == 1)
        _ = store.handle(.move(.window(-1)))                                                            // 1 → 3: back round
        #expect(store.strip?.marked == 3)
    }

    @Test("only a pointer that moved marks: cards sliding under a still mouse do not take the marking")
    func stillPointerDoesNotMark() async {
        let (_, store) = await stripOnTeams()
        store.notePointer(CGPoint(x: 500, y: 300))                                     // where the mouse rests as the strip opens
        store.point(1, at: CGPoint(x: 500, y: 300))                               // a card slid under it
        #expect(store.strip?.marked == 3)
        store.point(1, at: CGPoint(x: 520, y: 300))                               // the hand moved
        #expect(store.strip?.marked == 1)
        _ = store.handle(.move(.window(1)))
        store.point(1, at: CGPoint(x: 520, y: 300))                               // the row turned under a still hand
        #expect(store.strip?.marked == 2)
    }

    @Test("keys move the carousel's centre with the marking; the pointer marks but leaves the centre, or the row would slide under a still hand")
    func pointerLeavesTheCentre() async {
        let (_, store) = await stripOnTeams()
        #expect(store.strip?.centre == 3)                                              // opens centred on the marking
        store.point(1, at: CGPoint(x: 1, y: 0))
        store.point(9, at: CGPoint(x: 2, y: 0))                                         // not the app's: ignored
        #expect(store.strip?.marked == 1 && store.strip?.centre == 3)
        _ = store.handle(.move(.window(1)))
        #expect(store.strip?.marked == 2 && store.strip?.centre == 2)
        _ = store.handle(.move(.window(-1)))
        #expect(store.strip?.centre == 1)
        _ = store.handle(.move(.window(1)))
        #expect(store.strip?.centre == 2)
    }

    @Test("a closed marked window hands the marking to the one that took its place; the map drops the strip")
    func stripKeepsMarkingThroughReload() async {
        let (runner, store) = await stripOnTeams()
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams"), oneWindow(2, "2", app: "Teams")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2", "3"]))
        store.point(3, at: CGPoint(x: 3, y: 0))
        await store.reload()
        #expect(store.strip?.marked == 2)
        store.endVisit()
        #expect(store.strip == nil)
    }

    @Test("a strip whose app has no window left is over: the host closes and gives the keyboard back, rather than a map that swallows every key")
    func stripEndsWithItsLastWindow() async {
        let (runner, store) = await stripOnTeams()
        var done: [Bool] = []
        store.onShotDone = { done.append($0) }
        runner.setState(windows: "[" + [oneWindow(9, "1", app: "Slack", bundleId: "com.slack")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1"]))
        await store.reload()
        #expect(store.strip == nil && done == [true])
        #expect(store.handle(.character("s")) == .setQuery("s"))                      // the keys are the map's again
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
        await store.reload()
        _ = store.summonApp(.bundleId("com.app"))
        await store.capturePreviews(maxSize: CGSize(width: 400, height: 300))
        #expect(bridge.captured == [[1, 9, 2, 3]])                  // Slack on 1 is drawn grey in the card; Slack on 3 is in no card
        #expect(store.pictures.previews[9]?.size.width == 400 && store.pictures.previews[7] == nil)
    }

    @Test("a workspace's pictures land together once all of its windows are taken, without waiting for the other workspaces")
    func picturesLandPerWorkspace() async throws {
        let bridge = FakeBridge()
        bridge.granted = true
        let store = OverviewStore(runner: ScriptRunner(windows: windowsJSON([(1, "1"), (2, "1"), (3, "2")]), workspaces: workspacesJSON(["1", "2"])), nativeSystem: bridge)
        await store.reload()
        for (taken, landed) in [(1, [Int]()), (2, [1, 2])] {
            bridge.holdAfter = taken
            let capture = Task { await store.capturePreviews(maxSize: CGSize(width: 100, height: 100)) }
            for _ in 0..<100 where !bridge.isHolding { await Task.yield() }
            try await Task.sleep(for: .milliseconds(80))
            #expect(bridge.isHolding && store.pictures.previews.keys.sorted() == landed)
            bridge.release()
            await capture.value
            #expect(store.pictures.previews.keys.sorted() == [1, 2, 3])
            store.endVisit()
        }
    }

    @Test("the cards land in reading order: a workspace that is in waits for the ones before it")
    func cardsLandInReadingOrder() async throws {
        let bridge = FakeBridge()
        bridge.granted = true
        bridge.blank = [1]                                                       // workspace 1 never completes
        bridge.holdAfter = 2
        let store = OverviewStore(runner: ScriptRunner(windows: windowsJSON([(1, "1"), (2, "2"), (3, "3")]), workspaces: workspacesJSON(["1", "2", "3"])), nativeSystem: bridge)
        await store.reload()
        let capture = Task { await store.capturePreviews(maxSize: CGSize(width: 100, height: 100)) }
        for _ in 0..<100 where !bridge.isHolding { await Task.yield() }
        try await Task.sleep(for: .milliseconds(80))
        #expect(bridge.isHolding && store.pictures.previews.isEmpty)                     // 2 is in, behind 1
        bridge.release()
        await capture.value                                                      // the capture is in: the rest land
        #expect(store.pictures.previews.keys.sorted() == [2, 3])
    }

    @Test("cards that are in together still land one after the other, so the wave can be seen")
    func cardsLandApart() async {
        let bridge = FakeBridge()
        bridge.granted = true
        let store = OverviewStore(runner: ScriptRunner(windows: windowsJSON([(1, "1"), (2, "2")]), workspaces: workspacesJSON(["1", "2"])), nativeSystem: bridge)
        await store.reload()
        let capture = Task { await store.capturePreviews(maxSize: CGSize(width: 100, height: 100)) }
        await waitUntil { store.pictures.previews[1] != nil }
        #expect(store.pictures.previews[2] == nil)
        await capture.value
        #expect(store.pictures.previews.keys.sorted() == [1, 2])
    }

    @Test("a tile that draws a picture larger than it was taken asks for it again at its size, once; a smaller one asks nothing")
    func picturesTakenAgainLarger() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(3), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.granted = true
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        await store.reload()
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        store.pictures.want(1, pixels: CGSize(width: 300, height: 200))           // drawn three times larger
        store.pictures.want(2, pixels: CGSize(width: 80, height: 50))             // drawn smaller: as taken
        await waitUntil { (store.pictures.previews[1]?.size.width ?? 0) >= 300 }               // landed with its capture
        #expect(bridge.captured.last == [1])
        #expect(store.pictures.previews[2]!.size.width == 100)
        store.pictures.want(1, pixels: CGSize(width: 300, height: 200))           // has it now
        try? await Task.sleep(for: .milliseconds(300))
        #expect(bridge.captured.count == 2)
    }

    @Test("a picture that cannot be had larger — the window is no bigger — is not asked for again")
    func pictureAskedForOnce() async {
        let runner = ScriptRunner()
        runner.setState(windows: teams(1), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.granted = true
        bridge.largest = CGSize(width: 150, height: 150)
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        await store.reload()
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        store.pictures.want(1, pixels: CGSize(width: 300, height: 300))
        await waitUntil { bridge.captured.count >= 2 }
        store.pictures.want(1, pixels: CGSize(width: 300, height: 300))           // still smaller than drawn: asked already
        try? await Task.sleep(for: .milliseconds(300))
        #expect(bridge.captured.count == 2 && store.pictures.previews[1]!.size.width == 150)
    }

    // MARK: Pictures after a move

    /// A store on screen with its pictures in: summoned, measured, captured.
    private func summoned(_ runner: ScriptRunner, _ bridge: FakeBridge) async -> OverviewStore {
        bridge.granted = true
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
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
        #expect(store.pictures.sizes[2] == CGSize(width: 600, height: 200))           // the fresh size, not the summon's
    }

    @Test("a window that resizes in steps is taken once, when it stands still, in its last shape; the cards follow it on the way")
    func takenOnceSettled() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let store = await summoned(runner, bridge)
        store.send(.event(.changed))
        for width in [400.0, 500.0, 600.0] {                                            // the app on its way
            try? await Task.sleep(for: .milliseconds(35))
            bridge.sizes[2] = CGSize(width: width, height: 200)
        }
        await waitUntil { bridge.captured.count >= 2 }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(bridge.captured == [[1, 2], [2]] && (store.pictures.previews[2]?.size.height ?? 0) < 40)   // once, 100 × 33
    }

    @Test("a refresh cut off by the next while the windows still settle takes no pictures: the next takes them")
    func cutOffWhileSettlingTakesNothing() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let store = await summoned(runner, bridge)
        store.send(.event(.changed))
        for width in [400.0, 500.0, 600.0] {                                            // the app on its way
            try? await Task.sleep(for: .milliseconds(35))
            bridge.sizes[2] = CGSize(width: width, height: 200)
            if width == 500 { store.send(.event(.changed)) }                            // AeroSpace's next event, mid-settle
        }
        await waitUntil { bridge.captured.count >= 2 }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(bridge.captured == [[1, 2], [2]])                                       // the cut-off refresh took none
    }

    @Test("a refresh cut off by the next while it takes pictures loses nothing: the next takes them, nothing having been stored")
    func overlappingRefreshesKeepTheirPictures() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let store = await summoned(runner, bridge)
        bridge.holdAfter = 0
        bridge.sizes[2] = CGSize(width: 600, height: 200)                               // the neighbour widened into the hole
        store.send(.event(.changed))
        await waitUntil { bridge.isHolding }
        bridge.holdAfter = nil
        store.send(.event(.changed))                                                    // AeroSpace's next event
        try? await Task.sleep(for: .milliseconds(50))
        bridge.release()
        await waitUntil { (store.pictures.previews[2]?.size.height ?? 0) < 40 }
        #expect((store.pictures.previews[2]?.size.height ?? 0) < 40)                            // taken in the new shape, 100 × 33, not the old 100 × 67
    }

    @Test("focus moves at once: after a workspace switch the ring is on the window AeroSpace's event named, before any read, while the layout waits for the windows to settle")
    func focusMovesAtOnce() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "4")]), workspaces: workspacesJSON(["1", "4"]))
        runner.setFocus(windowId: 1, workspace: "1")
        let store = await summoned(runner, bridge)
        #expect(store.ringWindowId == 1)
        runner.setState(windows: windowsJSON([(1, "1"), (2, "4"), (3, "4")]), workspaces: workspacesJSON(["1", "4"]))   // a window came too
        runner.setFocus(windowId: 2, workspace: "4")
        store.send(.event(.focusChanged(windowId: 2, workspace: "4")))                 // `aerospace workspace 4`
        #expect(store.ringWindowId == 2)                                                // applied at once: send is a call, not a queue
        await waitUntil { store.ringWindowId == 2 }
        #expect(store.model.focusedWorkspace == "4")
        #expect(windowIds(store) == [1, 2])                                            // the layout not yet: still settling
        await waitUntil { windowIds(store) == [1, 2, 3] }
    }

    @Test("the card changes once, read a moment after the key's binding-triggered, which comes before its commands run: the new layout, the settled sizes and the new pictures together")
    func cardChangesOnce() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = await summoned(runner, bridge)
        store.send(.event(.changed))                                                    // the key: its commands not run yet
        try? await Task.sleep(for: .milliseconds(5))
        runner.setState(windows: windowsJSON([(1, "2"), (2, "1")]), workspaces: workspacesJSON(["1", "2"]))   // now they have
        bridge.sizes[2] = CGSize(width: 600, height: 200)                               // and the neighbour widened into the hole
        try? await Task.sleep(for: .milliseconds(40))                                    // read, still settling
        #expect(workspaceOf(store, 1) == "1")
        await waitUntil { workspaceOf(store, 1) == "2" }
        #expect(store.pictures.sizes[2]?.width == 600 && (store.pictures.previews[2]?.size.height ?? 0) < 40)  // with it, not after
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
    }

    @Test("a hidden overview takes no pictures on a refresh")
    func hiddenOverviewTakesNone() async {
        let runner = ScriptRunner(), bridge = FakeBridge()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = await summoned(runner, bridge)
        store.endVisit()
        runner.setState(windows: windowsJSON([(1, "1"), (4, "1")]), workspaces: workspacesJSON(["1"]))
        store.send(.event(.changed))
        await waitUntil { windowIds(store) == [1, 4] }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(bridge.captured.count == 1)
    }

    // MARK: Actions

    @Test("typed inputs drive the store through the send() ingress")
    func typedInputsDriveStore() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = started(runner)

        store.send(.loaded(result([("1", [1, 2])])))
        await waitUntil { windowIds(store) == [1, 2] }

        // An action shares the same ingress: it runs the CLI, then reconciles against
        // reality. AeroSpace now lists nothing, so the tile drops.
        runner.setState(windows: "[]", workspaces: workspacesJSON(["1"]))
        store.send(.action(.closeWindow(1)))
        await waitUntil { windowIds(store).isEmpty }
        #expect(runner.didRun(["close", "--window-id", "1"]))
        #expect(windowIds(store).isEmpty)
    }

    @Test("focus actions run their command and leave the model alone", arguments: [
        (AeroControlAction.focusWorkspace("2"), ["workspace", "2"]),
        (AeroControlAction.focusWindow(5), ["focus", "--window-id", "5"]),
    ])
    func focusActionsRunCommandOnly(action: AeroControlAction, argv: [String]) async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let before = windowIds(store)

        store.send(.action(action))
        await waitUntil { runner.didRun(argv) }
        // The overview dismisses on a focus action; there is nothing left to reconcile.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(windowIds(store) == before)
    }

    @Test("focusing the window AeroSpace already has focused moves nothing there, so the host gives its app the keyboard itself; any other, AeroSpace does")
    func focusOnTheFocusedWindow() async {
        let (_, store) = await loaded(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]), focus: (2, "1"))
        var done: [Bool] = []
        store.onShotDone = { done.append($0) }
        store.send(.action(.focusWindow(2)))
        store.send(.action(.focusWindow(1)))
        #expect(done == [true, false])
    }

    // WORKAROUND for AeroSpace issue 101: https://github.com/nikitabobko/AeroSpace/issues/101
    @Test("a focus AeroSpace did not carry out, its focus elsewhere a moment later, is asked for once more; one it did, not again", arguments: [(1, 2), (5, 1)])
    func focusAgainIfMissed(focusedAfter: Int, focusCommands: Int) async {
        let runner = ScriptRunner(windows: windowsJSON([(1, "1"), (5, "2")]), workspaces: workspacesJSON(["1", "2"]))
        runner.setFocus(windowId: focusedAfter, workspace: "1")                          // what AeroSpace says once it is done
        let store = started(runner)
        store.send(.action(.focusWindow(5)))
        try? await Task.sleep(for: .milliseconds(600))
        #expect(runner.commandsRun.filter { $0 == ["focus", "--window-id", "5"] }.count == focusCommands)
    }

    @Test("moveWindow runs its command and reconciles the tile to its new workspace")
    func moveWindowReconciles() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        #expect(workspaceOf(store, 1) == "1")

        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        store.send(.action(.moveWindow(windowId: 1, toWorkspace: "2")))
        await waitUntil { runner.didRun(["move-node-to-workspace", "--window-id", "1", "--focus-follows-window", "2"]) }
        await waitUntil { workspaceOf(store, 1) == "2" }
    }

    @Test("a burst of actions collapses to the latest reality")
    func burstReconcilesToLatest() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1"), (2, "1"), (3, "1")]), workspaces: workspacesJSON(["1"]))
        #expect(windowIds(store) == [1, 2, 3])

        // Every reconcile re-reads the SAME latest reality, so the newest-wins generation
        // stamp collapses the burst to the final state.
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        store.send(.action(.closeWindow(2)))
        store.send(.action(.closeWindow(3)))

        await waitUntil { windowIds(store) == [1] }
    }

    @Test("a content change invalidates the observable model; a no-op reload does not")
    func contentChangeInvalidatesModel() async {
        let (runner, store) = await loaded(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))

        let invalidations = ModelInvalidationCounter(store)
        try? await Task.sleep(for: .milliseconds(20))
        let before = invalidations.count

        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        await store.reload()
        await waitUntil { workspaceOf(store, 1) == "2" }
        await waitUntil { invalidations.count > before }

        // A reload that returns identical state must not reassign `model`, so no-op
        // readings never re-render the panel (avoids flashing / mid-hover resets).
        let afterChange = invalidations.count
        await store.reload()
        await store.reload()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(invalidations.count == afterChange)
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
        await store.reload()

        await store.measurePreviews()
        #expect(store.pictures.sizes.count == 2)                 // the grid's shape, before any picture
        await store.capturePreviews(maxSize: CGSize(width: 100, height: 100))
        #expect(bridge.captured == [[1, 2]])
        #expect(store.pictures.previews.count == 2)

        store.endVisit()
        #expect(store.pictures.previews.isEmpty && store.pictures.sizes.isEmpty)
    }

    @Test("an app's icon and a window's live picture are the bridge's, through the picture store")
    func iconsAndLive() {
        let bridge = FakeBridge()
        let store = OverviewStore(runner: ScriptRunner(), nativeSystem: bridge)
        #expect(store.pictures.icon(for: "com.app") === bridge.icon)
        #expect(store.pictures.live(1, pixels: CGSize(width: 10, height: 10)) === bridge.live)
    }

    @Test("without Screen Recording a capture stores nothing")
    func permission() async {
        let runner = ScriptRunner(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        let store = OverviewStore(runner: runner, nativeSystem: bridge)

        await store.capturePreviews(maxSize: CGSize(width: 10, height: 10))
        #expect(store.pictures.previews.isEmpty)
    }
}
