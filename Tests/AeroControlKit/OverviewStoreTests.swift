import AppKit
import Observation
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
    func windowCloseSignals() -> AsyncStream<Void> { AsyncStream { _ in } }
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

    @Test("a same-monitor content change invalidates the observable model; a no-op reload does not")
    func contentChangeInvalidatesModel() async {
        let runner = FakeRunner()
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
        runner.send("{\"_event\":\"focused-workspace-changed\",\"workspace\":\"2\",\"prevWorkspace\":\"1\"}")

        await waitUntil { workspaceOf(store, 1) == "2" }
        #expect(workspaceOf(store, 1) == "2")
        #expect(await invalidations.count > before)

        // A reload that returns identical state must not reassign `model`, so no-op
        // reconciles never re-render the panel (avoids flashing / mid-hover resets).
        let afterChange = await invalidations.count
        runner.send("{\"_event\":\"binding-triggered\"}")
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await invalidations.count == afterChange)
    }

    @Test("a burst of reloads to the same state invalidates the model at most once")
    func rapidRefreshesRenderOnce() async {
        let runner = FakeRunner()
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
            runner.send("{\"_event\":\"binding-triggered\"}")
        }

        await waitUntil { workspaceOf(store, 1) == "2" }
        try? await Task.sleep(for: .milliseconds(150))
        #expect(workspaceOf(store, 1) == "2")
        let delta = await invalidations.count - before
        #expect(delta == 1, "burst to one new state must render once, got \(delta)")
    }
}

/// Counts how many times the store's `@Observable` `model` invalidates — i.e. how many
/// times SwiftUI's `NSHostingView` would re-render. Re-registers its observation after
/// each change, so it tallies a running count over the test's lifetime.
@MainActor
private final class ModelInvalidationCounter {
    private(set) var count = 0
    private let store: OverviewStore

    init(_ store: OverviewStore) {
        self.store = store
        register()
    }

    private func register() {
        withObservationTracking {
            _ = store.model
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.count += 1
                self?.register()
            }
        }
    }
}
