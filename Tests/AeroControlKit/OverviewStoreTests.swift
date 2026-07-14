import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// MARK: - Fake ports

/// Scriptable stand-in for the aerospace CLI. `run` returns the currently-programmed
/// list JSON; `subscribe` exposes a continuation so a test can push raw event lines.
private final class FakeRunner: AerospaceProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var windowsJSON = "[]"
    private var workspacesJSON = "[]"
    private var monitorsJSON = "[]"

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

    func setState(windows: String, workspaces: String) {
        withLock {
            windowsJSON = windows
            workspacesJSON = workspaces
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
    func appIcon(bundleId: String) -> NSImage { NSImage() }
    func appTerminations() -> AsyncStream<Void> { AsyncStream { _ in } }
}

/// Collects the store's typed outputs off its `AsyncStream` for assertions.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [OverviewOutput] = []
    func append(_ output: OverviewOutput) {
        lock.lock(); defer { lock.unlock() }
        items.append(output)
    }
    func count(of output: OverviewOutput) -> Int {
        lock.lock(); defer { lock.unlock() }
        return items.filter { $0 == output }.count
    }
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
private func workspaceOf(_ store: OverviewStore, _ id: Int) -> String? {
    for ws in store.model.workspaces where ws.windows.contains(where: { $0.windowId == id }) {
        return ws.name
    }
    return nil
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

    @Test("closing a window runs the command and the reload drops the tile")
    func closeReloadsAndRemovesTile() async {
        let runner = FakeRunner()
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

    @Test("a reload mirrors AeroSpace verbatim — a window it no longer lists disappears")
    func reloadMirrorsAerospace() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(1, "1"), (2, "1")]), workspaces: workspacesJSON(["1"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()
        #expect(windowIds(store) == [1, 2])

        // AeroSpace dropped window 2; the next event-driven reload reflects that exactly —
        // no CGWindowList cross-check, no suppression. AeroSpace is the source of truth.
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1"]))
        await waitUntil { runner.isSubscribed }
        runner.send("{\"_event\":\"binding-triggered\"}")

        await waitUntil { windowIds(store) == [1] }
        #expect(windowIds(store) == [1])
    }

    @Test("a same-monitor content change emits contentChanged; a no-op reload does not")
    func contentChangeEmitsOutput() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        let outputs = OutputCollector()
        let task = Task { for await output in store.outputs { outputs.append(output) } }
        // Let the collector attach and drain start-up outputs.
        try? await Task.sleep(for: .milliseconds(20))

        // Window 1 moves from ws "1" to ws "2" on the same monitor: AeroSpace now lists it
        // under "2" and emits a workspace-changed event that drives a reconcile. The
        // manually-hosted panel doesn't auto-observe, so the store must signal the change.
        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        await waitUntil { runner.isSubscribed }
        runner.send("{\"_event\":\"focused-workspace-changed\",\"workspace\":\"2\",\"prevWorkspace\":\"1\"}")

        await waitUntil { workspaceOf(store, 1) == "2" }
        #expect(workspaceOf(store, 1) == "2")
        #expect(outputs.count(of: .contentChanged) >= 1)

        // A reload that returns identical state must not emit another contentChanged, so
        // no-op reconciles never rebuild the panel (avoids flashing / mid-hover resets).
        let before = outputs.count(of: .contentChanged)
        runner.send("{\"_event\":\"binding-triggered\"}")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(outputs.count(of: .contentChanged) == before)

        task.cancel()
    }

    @Test("a burst of reloads to the same state stresses the UI with at most one render")
    func rapidRefreshesRenderOnce() async {
        let runner = FakeRunner()
        runner.setState(windows: windowsJSON([(1, "1")]), workspaces: workspacesJSON(["1", "2"]))
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        await store.start()

        let outputs = OutputCollector()
        let task = Task { for await output in store.outputs { outputs.append(output) } }
        // Let the collector attach and drain buffered start-up outputs (the initial load
        // emits its own contentChanged), then measure the burst as a delta from here.
        try? await Task.sleep(for: .milliseconds(20))
        let before = outputs.count(of: .contentChanged)

        // AeroSpace now reports window 1 on ws "2". Fire a burst of refresh-driving events:
        // every reload re-reads the SAME new state, so only the first apply differs from the
        // model. Mirroring AeroSpace on every event must not stress the UI — the store emits
        // exactly one contentChanged for the burst, and no-op reloads emit none.
        runner.setState(windows: windowsJSON([(1, "2")]), workspaces: workspacesJSON(["1", "2"]))
        await waitUntil { runner.isSubscribed }
        for _ in 0..<5 {
            runner.send("{\"_event\":\"binding-triggered\"}")
        }

        await waitUntil { workspaceOf(store, 1) == "2" }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(workspaceOf(store, 1) == "2")
        #expect(outputs.count(of: .contentChanged) - before == 1, "burst to one new state must render once, got \(outputs.count(of: .contentChanged) - before)")

        task.cancel()
    }
}
