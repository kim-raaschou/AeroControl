import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// One set of test doubles and JSON builders for the whole suite. There used to be four
// hand-rolled runners and three bridges across four files, each a near-copy of the next.

/// Scriptable stand-in for AeroSpace: `run` serves the currently-programmed list JSON and
/// records every argv, so a test can assert an action's command and tell action commands
/// apart from the list-* reads of a reload. `subscribe` exposes its continuation so a test
/// can push raw event lines.
final class ScriptRunner: AerospaceProcessRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var windowsJSON = "[]"
    private var workspacesJSON = "[]"
    private var subCont: AsyncThrowingStream<String, Error>.Continuation?
    private var ranArgs: [[String]] = []
    private var focusedWindowJSON = "[]"
    private var focusedWorkspaceJSON = "[]"
    /// When set, every command throws — an AeroSpace that is not answering.
    var failing = false
    /// Answer the lists but refuse the two `--focused` reads.
    var refuseFocusReads = false
    /// Whether this AeroSpace knows `%{window-layout-rect}` (the owner's branch). Off by
    /// default, like every AeroSpace release so far.
    var acceptsLayoutRects = false

    init(windows: String = "[]", workspaces: String = "[]") {
        windowsJSON = windows
        workspacesJSON = workspaces
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    /// True once the store's subscribe listener has attached.
    var isSubscribed: Bool { withLock { subCont != nil } }

    var commandsRun: [[String]] { withLock { ranArgs } }
    func didRun(_ argv: [String]) -> Bool { withLock { ranArgs.contains(argv) } }

    func setState(windows: String, workspaces: String) {
        withLock { windowsJSON = windows; workspacesJSON = workspaces }
    }

    /// What the two `--focused` reads answer.
    func setFocus(windowId: Int?, workspace: String?) {
        withLock {
            focusedWindowJSON = windowId.map { "[\(oneWindow($0, workspace ?? ""))]" } ?? "[]"
            focusedWorkspaceJSON = workspace.map { "[{\"workspace\":\"\($0)\",\"monitor-id\":1}]" } ?? "[]"
        }
    }

    /// Delivers a raw event line to the store's subscribe listener.
    func sendEvent(_ line: String) {
        let cont = withLock { subCont }
        cont?.yield(line)
    }

    func run(_ args: [String]) async throws -> String {
        withLock { ranArgs.append(args) }
        if failing { throw AerospaceSocketError.io("no aerospace") }
        let focused = args.contains("--focused")
        if focused, refuseFocusReads { throw AerospaceSocketError.io("no focus") }
        if args.contains(where: { $0.contains("window-layout-rect") }), !acceptsLayoutRects {
            throw AerospaceSocketError.commandFailed(arguments: args, exitCode: 1,
                                                     stderr: "ERROR: Failed to parse <output-format>. Can't parse 'window-layout-rect'.", serverVersion: nil)
        }
        switch (args.first ?? "", focused) {
        case ("list-workspaces", true): return withLock { focusedWorkspaceJSON }
        case ("list-workspaces", false): return withLock { workspacesJSON }
        case ("list-windows", true): return withLock { focusedWindowJSON }
        case ("list-windows", false): return withLock { windowsJSON }
        default: return ""
        }
    }

    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            self.withLock { self.subCont = cont }
            cont.onTermination = { [weak self] _ in self?.withLock { self?.subCont = nil } }
        }
    }
}

/// Native bridge a test can drive: icons and preview capture.
@MainActor
final class FakeBridge: NativeApiBridge {
    /// Screen Recording granted? Drives `previewsAvailable`.
    var granted = false
    var accessRequests = 0
    /// Every window-id list the store has asked to capture.
    var captured: [[Int]] = []
    /// Bundle ids of apps macOS reports hidden.
    var hidden: Set<String> = []
    func hiddenBundleIds() -> Set<String> { hidden }

    func appIcon(bundleId: String) -> NSImage { NSImage() }
    var canCapturePreviews: Bool { granted }
    func requestPreviewAccess() { accessRequests += 1 }
    /// What the window server reports per window; 300 × 200 for any not listed.
    var sizes: [Int: CGSize] = [:]
    /// How many times sizes were read.
    var measured = 0
    func previewSizes(windowIds: [Int]) async -> [Int: CGSize] {
        measured += 1
        return Dictionary(uniqueKeysWithValues: windowIds.map { ($0, sizes[$0] ?? CGSize(width: 300, height: 200)) })
    }
    /// The largest picture a window gives, as a real window gives none larger than itself.
    var largest: CGSize?
    /// Windows that give no picture, as one the window server cannot capture.
    var blank: Set<Int> = []
    /// When set, a capture delivers this many pictures and then waits for `release()`.
    var holdAfter: Int?
    private var held: CheckedContinuation<Void, Never>?
    var isHolding: Bool { held != nil }
    func release() { held?.resume(); held = nil }
    func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async {
        captured.append(windowIds)
        for (n, id) in windowIds.enumerated() {
            if n == holdAfter { await withCheckedContinuation { held = $0 } }
            guard !blank.contains(id), !Task.isCancelled else { continue }       // a cancelled capture gives nothing, as ScreenCaptureKit's
            // In the window's shape, as large as fits — like a real capture.
            let box = largest.map { CGSize(width: min($0.width, maxSize.width), height: min($0.height, maxSize.height)) } ?? maxSize
            let shape = sizes[id] ?? CGSize(width: 300, height: 200)
            let scale = min(box.width / shape.width, box.height / shape.height)
            deliver(id, NSImage(size: CGSize(width: shape.width * scale, height: shape.height * scale)))
        }
    }
}

// MARK: - JSON and model builders

/// One `list-windows` entry. The app name and title are parameters so a test can filter on
/// them; a nil title is left out of the JSON entirely, like a window that has none.
func oneWindow(_ id: Int, _ ws: String, app: String = "App", title: String? = nil, bundleId: String = "com.app") -> String {
    "{\"window-id\":\(id),\"app-name\":\"\(app)\",\"app-bundle-id\":\"\(bundleId)\","
        + (title.map { "\"window-title\":\"\($0)\"," } ?? "")
        + "\"workspace\":\"\(ws)\",\"window-parent-container-layout\":\"h_tiles\",\"monitor-id\":1}"
}

func windowsJSON(_ entries: [(Int, String)]) -> String {
    "[" + entries.map { oneWindow($0.0, $0.1) }.joined(separator: ",") + "]"
}

func workspacesJSON(_ names: [String]) -> String {
    "[" + names.map { "{\"workspace\":\"\($0)\",\"monitor-id\":1}" }.joined(separator: ",") + "]"
}

/// A typed load result from `(workspaceName, [windowId])` pairs.
func result(_ spec: [(String, [Int])]) -> OverviewResult {
    OverviewResult(workspaces: spec.map { name, ids in
        WorkspaceInfo(name: name, windows: ids.map { WindowInfo(windowId: $0, appName: "App", bundleId: "com.app") })
    })
}

// MARK: - Store probes

@MainActor
func windowIds(_ store: OverviewStore) -> [Int] {
    store.model.workspaces.flatMap { $0.windows.map(\.windowId) }.sorted()
}

@MainActor
func workspaceOf(_ store: OverviewStore, _ id: Int) -> String? {
    store.model.workspaces.first { $0.windows.contains { $0.windowId == id } }?.name
}

@MainActor
func waitUntil(_ cond: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if cond() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Counts how many times the store's `@Observable` `model` invalidates — i.e. how many
/// times SwiftUI's `NSHostingView` would re-render. Re-registers after each change.
@MainActor
final class ModelInvalidationCounter {
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
