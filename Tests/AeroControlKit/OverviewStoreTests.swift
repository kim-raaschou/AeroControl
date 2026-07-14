import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// MARK: - Fake ports

/// Scriptable stand-in for the aerospace CLI. `run` returns the currently-programmed
/// list JSON; `subscribe` exposes a continuation so a test can push raw event lines.
/// A one-shot gate lets a test park the first post-arm `list-windows` load so it can
/// observe the refresh coordinator's coalescing (requests during an in-flight load fold
/// into a single trailing reload).
private final class FakeRunner: AerospaceProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var windowsJSON = "[]"
    private var workspacesJSON = "[]"
    private var monitorsJSON = "[]"
    private var _count = 0
    private var gateArmed = false
    private var parkContinuation: CheckedContinuation<Void, Never>?

    private var _continuation: AsyncThrowingStream<String, Error>.Continuation?

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    var isSubscribed: Bool {
        withLock { _continuation != nil }
    }

    /// Delivers a raw event line to the store's subscribe listener.
    func send(_ line: String) {
        let cont = withLock { _continuation }
        cont?.yield(line)
    }

    var listWindowsCount: Int {
        withLock { _count }
    }

    func setState(windows: String, workspaces: String) {
        withLock {
            windowsJSON = windows
            workspacesJSON = workspaces
        }
    }

    func armGate() {
        withLock { gateArmed = true }
    }

    func releaseGate() async {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            let cont: CheckedContinuation<Void, Never>? = withLock {
                let c = parkContinuation
                parkContinuation = nil
                return c
            }
            if let cont {
                cont.resume()
                return
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    func run(_ args: [String]) async throws -> String {
        let cmd = args.first ?? ""
        if cmd == "list-workspaces" {
            return withLock { workspacesJSON }
        }
        if cmd == "list-monitors" {
            return withLock { monitorsJSON }
        }
        if cmd != "list-windows" {
            return ""
        }
        let parked: Bool = withLock {
            _count += 1
            let park = gateArmed
            gateArmed = false
            return park
        }
        if parked {
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                withLock { parkContinuation = cont }
            }
        }
        return withLock { windowsJSON }
    }

    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { cont in
            self.withLock { self._continuation = cont }
        }
    }
}

@MainActor
private final class FakeBridge: NativeApiBridge {
    var live: Set<Int> = []
    func liveWindowIds() -> Set<Int> { live }
    func appIcon(bundleId: String) -> NSImage { NSImage() }
    func appTerminations() -> AsyncStream<Void> { AsyncStream { _ in } }
}

// MARK: - Helpers

private func oneWindow(_ id: Int, _ ws: String) -> String {
    var s = "{\"window-id\":"
    s += String(id)
    s += ",\"app-name\":\"App\",\"app-bundle-id\":\"com.app\",\"workspace\":\""
    s += ws
    s += "\",\"window-parent-container-layout\":\"h_tiles\",\"monitor-id\":1}"
    return s
}

private func windowsJSON(_ entries: [(Int, String)]) -> String {
    let parts = entries.map { oneWindow($0.0, $0.1) }
    return "[" + parts.joined(separator: ",") + "]"
}

private func workspacesJSON(_ names: [String]) -> String {
    let parts = names.map { "{\"workspace\":\"" + $0 + "\",\"monitor-id\":1}" }
    return "[" + parts.joined(separator: ",") + "]"
}

@MainActor
private func windowIds(_ store: OverviewStore) -> [Int] {
    var ids: [Int] = []
    for ws in store.model.workspaces {
        for w in ws.windows {
            ids.append(w.windowId)
        }
    }
    return ids.sorted()
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
@Suite("OverviewStore")
struct OverviewStoreTests {

    @Test("dispatch(closeWindow) removes the tile immediately")
    func optimisticCloseRemovesTile() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(100, "1"), (200, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        // The window is closed for real, so a later reconcile can't resurrect it.
        runner.setState(windows: windowsJSON([(200, "1")]), workspaces: workspacesJSON(["1"]))
        await store.dispatch(.closeWindow(100))

        let ids = windowIds(store)
        #expect(!ids.contains(100))
        #expect(ids.contains(200))
    }

    @Test("a refresh event reloads and applies the latest state")
    func refreshAppliesFetchedState() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        await waitUntil { runner.isSubscribed }
        runner.send("{\"_event\":\"binding-triggered\"}")

        await waitUntil { windowIds(store).contains(2) }
        #expect(windowIds(store) == [1, 2])
    }

    @Test("a reload drops windows the window server no longer lists (dead-tile race)")
    func reloadDropsDeadWindows() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.live = [1, 2]
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        await store.start()
        #expect(windowIds(store) == [1, 2])

        // Window 2 is really gone (the window server dropped it), but AeroSpace still
        // lists it for a beat and emits no close event. A reload must not resurrect it.
        bridge.live = [1]
        await waitUntil { runner.isSubscribed }
        runner.send("{\"_event\":\"binding-triggered\"}")

        await waitUntil { windowIds(store) == [1] }
        #expect(windowIds(store) == [1])
    }

    @Test("a newly detected window is kept even before the window server lists it (open-lag race)")
    func openLagKeepsNewWindow() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.live = [1]
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        await store.start()
        #expect(windowIds(store) == [1])

        // A new window opens: AeroSpace lists it and emits window-detected immediately, but
        // the window server hasn't composited it into CGWindowList yet (live still lacks 2).
        // The one-shot detect refresh must NOT suppress the brand-new tile.
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        await waitUntil { runner.isSubscribed }
        runner.send("{\"_event\":\"window-detected\",\"windowId\":2,\"workspace\":\"1\"}")

        await waitUntil { windowIds(store).contains(2) }
        #expect(windowIds(store) == [1, 2])
    }

    @Test("an empty live set never prunes the overview")
    func emptyLiveSetKeepsAll() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let bridge = FakeBridge()
        bridge.live = []
        let store = OverviewStore(runner: runner, nativeSystem: bridge)
        await store.start()

        await waitUntil { runner.isSubscribed }
        runner.send("{\"_event\":\"binding-triggered\"}")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(windowIds(store) == [1, 2])
    }

    @Test("rapid refresh events coalesce into at most one trailing reload")
    func rapidRefreshesCoalesce() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        let baseline = runner.listWindowsCount

        // Park the next load, then fire a burst of refresh-driving events. The first
        // request starts (and parks) a load; the rest only mark the state dirty.
        await waitUntil { runner.isSubscribed }
        runner.armGate()
        for _ in 0..<5 {
            runner.send("{\"_event\":\"binding-triggered\"}")
        }
        await waitUntil { runner.listWindowsCount == baseline + 1 }
        await runner.releaseGate()

        try? await Task.sleep(for: .milliseconds(200))
        let loads = runner.listWindowsCount - baseline
        #expect(loads >= 1, "burst should have driven at least one reload, got \(loads)")
        #expect(loads <= 2, "expected <=2 loads for a 5-event burst, got \(loads)")
    }
}
