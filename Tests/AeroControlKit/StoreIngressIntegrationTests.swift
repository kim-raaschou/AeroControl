import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// Integration tests for the *single ingress*. After the inbox refactor every live
// driver — the AeroSpace subscribe stream, the native app-termination bridge, and
// user actions — funnels its typed `OverviewInput` into one serialized inbox. These
// tests drive the store across BOTH sources (and directly via `send`) and assert the
// reconciled model, exercising the native-bridge path that the unit suite never touched.

// MARK: - Scriptable ports

/// Scriptable stand-in for the aerospace CLI: `run` serves the currently-programmed
/// list JSON; `subscribe` exposes a continuation so a test can push raw event lines.
private final class ScriptRunner: AerospaceProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var windowsJSON = "[]"
    private var workspacesJSON = "[]"
    private var subCont: AsyncThrowingStream<String, Error>.Continuation?
    private var ranArgs: [[String]] = []

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    var isSubscribed: Bool { withLock { subCont != nil } }

    /// Every argv passed to `run`, in order — lets a test assert an action's CLI command
    /// (and distinguish action commands from the list-* reload reads).
    var commandsRun: [[String]] { withLock { ranArgs } }
    func didRun(_ argv: [String]) -> Bool { withLock { ranArgs.contains(argv) } }

    func setState(windows: String, workspaces: String) {
        withLock { windowsJSON = windows; workspacesJSON = workspaces }
    }

    /// Delivers a raw event line to the store's subscribe listener.
    func sendEvent(_ line: String) {
        let cont = withLock { subCont }
        cont?.yield(line)
    }

    func run(_ args: [String]) async throws -> String {
        withLock { ranArgs.append(args) }
        switch args.first ?? "" {
        case "list-workspaces": return withLock { workspacesJSON }
        case "list-windows": return withLock { windowsJSON }
        case "list-monitors": return "[]"
        default: return ""
        }
    }

    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            self.withLock { self.subCont = cont }
        }
    }
}

/// Native bridge whose termination stream a test can drive — the second input source,
/// previously stubbed with an empty stream and therefore never exercised.
@MainActor
private final class ScriptableBridge: NativeApiBridge {
    private var cont: AsyncStream<Void>.Continuation?
    private var closeCont: AsyncStream<Void>.Continuation?

    func appIcon(bundleId: String) -> NSImage { NSImage() }

    func appTerminations() -> AsyncStream<Void> {
        AsyncStream { c in self.cont = c }
    }

    func windowCloseSignals() -> AsyncStream<Void> {
        AsyncStream { c in self.closeCont = c }
    }

    /// True once the store's termination listener has subscribed.
    var isListening: Bool { cont != nil }

    /// True once the store's window-close doorbell listener has subscribed.
    var isWatchingCloses: Bool { closeCont != nil }

    /// Emits one app-termination signal.
    func terminate() { cont?.yield(()) }

    /// Rings the window-close doorbell once (a background mouse-up).
    func ringCloseDoorbell() { closeCont?.yield(()) }
}

/// Records the store's host-reaction callbacks for assertions.
private enum HostSignal: Equatable { case loaded, monitorsChanged, workspaceFocused }

private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [HostSignal] = []
    func append(_ output: HostSignal) {
        lock.lock(); defer { lock.unlock() }
        items.append(output)
    }
    func count(of output: HostSignal) -> Int {
        lock.lock(); defer { lock.unlock() }
        return items.filter { $0 == output }.count
    }
}

/// Wires a collector to a store's three host-reaction callbacks.
@MainActor private func collect(_ store: OverviewStore) -> OutputCollector {
    let outputs = OutputCollector()
    store.onLoaded = { outputs.append(.loaded) }
    store.onMonitorsChanged = { outputs.append(.monitorsChanged) }
    store.onWorkspaceFocused = { outputs.append(.workspaceFocused) }
    return outputs
}


// MARK: - Helpers

private func oneWindow(_ id: Int, _ ws: String) -> String {
    "{\"window-id\":\(id),\"app-name\":\"App\",\"app-bundle-id\":\"com.app\","
        + "\"workspace\":\"\(ws)\",\"window-parent-container-layout\":\"h_tiles\",\"monitor-id\":1}"
}

private func windowsJSON(_ entries: [(Int, String)]) -> String {
    "[" + entries.map { oneWindow($0.0, $0.1) }.joined(separator: ",") + "]"
}

private func workspacesJSON(_ names: [String]) -> String {
    "[" + names.map { "{\"workspace\":\"\($0)\",\"monitor-id\":1}" }.joined(separator: ",") + "]"
}

/// Builds a typed load result: a list of `(workspaceName, [windowId])`.
private func result(_ spec: [(String, [Int])]) -> OverviewResult {
    OverviewResult(workspaces: spec.map { name, ids in
        WorkspaceInfo(name: name, windows: ids.map { WindowInfo(windowId: $0, appName: "App", bundleId: "com.app") })
    })
}

/// Builds a typed load result placing each workspace on a specific monitor: a list of
/// `(workspaceName, monitorId, [windowId])`. Lets a test grow/shrink the *monitor set*.
private func resultM(_ spec: [(String, Int, [Int])]) -> OverviewResult {
    OverviewResult(workspaces: spec.map { name, monitorId, ids in
        WorkspaceInfo(
            name: name,
            windows: ids.map { WindowInfo(windowId: $0, appName: "App", bundleId: "com.app") },
            monitorId: monitorId
        )
    })
}

@MainActor
private func windowIds(_ store: OverviewStore) -> [Int] {
    store.model.workspaces.flatMap { $0.windows.map(\.windowId) }.sorted()
}

@MainActor
private func workspaceOf(_ store: OverviewStore, _ id: Int) -> String? {
    store.model.workspaces.first { $0.windows.contains { $0.windowId == id } }?.name
}

@MainActor
private func waitUntil(_ cond: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if cond() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - Tests

@MainActor
@Suite("OverviewStore single ingress")
struct StoreIngressIntegrationTests {

    @Test("the native app-termination source reconciles through the one inbox")
    func nativeTerminationSourceReconciles() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(100, "1"), (200, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = ScriptableBridge()
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
        let bridge = ScriptableBridge()
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
        let bridge = ScriptableBridge()
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
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
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
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
        await store.start()
        await waitUntil { runner.isSubscribed }

        runner.sendEvent("{\"_event\":\"focus-changed\",\"windowId\":1,\"workspace\":\"2\"}")
        await waitUntil { store.model.focusedWorkspace == "2" }
        #expect(store.model.focusedWindowId == 1)
        #expect(store.model.focusedWorkspace == "2")
        store.stop()
    }

    @Test("focused-workspace-changed sets focus and emits workspaceFocused")
    func workspaceChangedEvent() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
        let outputs = collect(store)
        await store.start()
        await waitUntil { runner.isSubscribed }

        runner.sendEvent("{\"_event\":\"focused-workspace-changed\",\"workspace\":\"2\",\"prevWorkspace\":\"1\"}")
        await waitUntil { store.model.focusedWorkspace == "2" }
        await waitUntil { outputs.count(of: .workspaceFocused) >= 1 }
        #expect(store.model.focusedWorkspace == "2")
        #expect(outputs.count(of: .workspaceFocused) >= 1)
        store.stop()
    }

    @Test("focused-monitor-changed sets focus and emits workspaceFocused")
    func monitorChangedEvent() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
        let outputs = collect(store)
        await store.start()
        await waitUntil { runner.isSubscribed }

        runner.sendEvent("{\"_event\":\"focused-monitor-changed\",\"workspace\":\"2\",\"monitorId\":1}")
        await waitUntil { store.model.focusedWorkspace == "2" }
        await waitUntil { outputs.count(of: .workspaceFocused) >= 1 }
        #expect(store.model.focusedWorkspace == "2")
        #expect(outputs.count(of: .workspaceFocused) >= 1)
        store.stop()
    }

    @Test("window-detected reconciles and picks up the new window")
    func windowDetectedEvent() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
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
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
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
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
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
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
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
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
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
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
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
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
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
    // The store's typed `outputs` channel is the single egress that `AeroControlApp`
    // maps to window-management calls: `.monitorsChanged` → `syncWindows()`,
    // `.workspaceFocused` → `syncWindows(force: false)`, `.loaded` →
    // `showErrorFallbackIfNeeded()`. Asserting the outputs here integration-tests *what*
    // OverlayWindowManager is told to do, deterministically and without AppKit. The
    // `.workspaceFocused` output is covered by the focus/monitor event tests above.

    @Test("a monitor-set change emits monitorsChanged; a same-monitor change does not")
    func monitorSetChangeEmitsMonitorsChanged() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())
        let outputs = collect(store)
        await store.start()
        // The initial load ([] → [1]) emits one `.monitorsChanged` asynchronously; wait
        // for it to settle so `before` captures a stable baseline.
        await waitUntil { outputs.count(of: .monitorsChanged) >= 1 }

        let before = outputs.count(of: .monitorsChanged)

        // A workspace appears on a SECOND monitor: the monitor set grows [1] → [1, 2], so the
        // host must re-sync the window. Exactly one `.monitorsChanged` for the set change.
        store.send(.loaded(resultM([("1", 1, [1]), ("5", 2, [5])])))
        await waitUntil { store.model.monitors.count == 2 }
        #expect(outputs.count(of: .monitorsChanged) - before == 1)

        // A same-monitor content change (a new window on monitor 1) must NOT re-emit
        // monitorsChanged — the monitor set is unchanged, so no window re-sync is needed.
        let afterGrow = outputs.count(of: .monitorsChanged)
        store.send(.loaded(resultM([("1", 1, [1, 2]), ("5", 2, [5])])))
        await waitUntil { windowIds(store) == [1, 2, 5] }
        #expect(outputs.count(of: .monitorsChanged) == afterGrow)

        store.stop()
    }

    @Test("the initial load emits loaded so the host can reveal or show an error")
    func initialLoadEmitsLoaded() async {
        let runner = ScriptRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: ScriptableBridge())

        // Attach before `start()` so the one-shot `.loaded` (fired on a later main-queue turn,
        // after the load's icon effects) is captured deterministically.
        let outputs = collect(store)
        await store.start()

        await waitUntil { outputs.count(of: .loaded) >= 1 }
        #expect(outputs.count(of: .loaded) == 1)

        store.stop()
    }
}
