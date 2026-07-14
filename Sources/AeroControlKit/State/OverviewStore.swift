import AppKit
import SwiftUI
import Common

/// The TEA runtime/store — NOT domain state. It owns the observable `model`
/// (the pure `OverviewModel` from Common), drives the pure `updateOverview`
/// reducer, and interprets its effects: running the aerospace CLI via the
/// `AerospaceProcessRunner` port, loading icons via `NativeApiBridge`, managing
/// subscription/termination task lifecycles, and firing host callbacks. The pure
/// state and transition logic live in Common; this class is the adapter-layer
/// engine that connects them to the live system and the UI.
@MainActor @Observable
public class OverviewStore {
    public private(set) var model = OverviewModel()

    let runner: AerospaceProcessRunner
    let nativeSystem: NativeApiBridge
    private(set) var icons: [Int: NSImage] = [:]
    /// monitorId -> AeroSpace's 1-based AppKit `NSScreen.screens` index, used to place
    /// each overlay on the correct display (AeroSpace's own `monitor-id` ordering does
    /// not necessarily match AppKit's screen ordering).
    public private(set) var monitorScreenIds: [Int: Int] = [:]
    public private(set) var error: String?
    public private(set) var isLoaded: Bool = false

    /// Typed output channel consumed by the host. Replaces the former
    /// `onMonitorsChanged` / `onLoaded` / `onWorkspaceFocused` closures.
    public let outputs: AsyncStream<OverviewOutput>
    private let outputContinuation: AsyncStream<OverviewOutput>.Continuation

    private var subscribeTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.runner = runner
        self.nativeSystem = nativeSystem
        (outputs, outputContinuation) = AsyncStream.makeStream()
    }

    private func emit(_ output: OverviewOutput) {
        outputContinuation.yield(output)
    }

    public func start() async {
        await initialLoad()
        startSubscribeListener()
        startTerminationListener()
        // Reveal only after the loaded effects (icon loading) have been applied,
        // so consumers show the HUD with icons already in place rather than
        // letting them pop in a frame later.
        fireLoadedAfterEffects()
    }

    /// Emits `.loaded` on a later main-queue turn so the effects dispatched by
    /// `apply(.loaded(...))` (notably icon loading) run first.
    private func fireLoadedAfterEffects() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.emit(.loaded)
            }
        }
    }

    private func initialLoad() async {
        // The aerospace binary can be momentarily unreachable when we start:
        // e.g. a `brew upgrade aerospace` leaves the /opt/homebrew/bin symlink
        // dangling for a beat, or at login we race ahead of the aerospace
        // daemon/PATH. A single failure here used to become a *permanent*
        // "Load error" because we never retried. Retry with backoff so a
        // transient startup hiccup recovers on its own.
        let maxAttempts = 5
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let result = try await loadOverview(using: runner)
                // Populate the monitor→NSScreen maps *before* applying `.loaded`, whose
                // `.monitorsChanged` effect drives the first `syncWindows()`. Otherwise
                // `monitorScreenIds` is still empty during that first sync and windows
                // fall back to the `monitorId - 1` guess, defeating the authoritative
                // `monitor-appkit-nsscreen-screens-id` mapping.
                if let monitors = try? await loadMonitors(using: runner) {
                    setMonitors(monitors)
                }
                apply(.loaded(result), animated: false)
                self.error = nil
                self.isLoaded = true
                return
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    // 200ms, 400ms, 600ms, 800ms — total < 2s worst case.
                    try? await Task.sleep(for: .milliseconds(200 * attempt))
                }
            }
        }
        if let lastError {
            self.error = "Load error: \(lastError.localizedDescription)"
        }
        self.isLoaded = true
    }

    private func setMonitors(_ monitors: [DecodedMonitor]) {
        let newScreenIds = Dictionary(
            monitors.compactMap { $0.nsscreenId > 0 ? ($0.monitorId, $0.nsscreenId) : nil },
            uniquingKeysWith: { first, _ in first }
        )
        let changed = newScreenIds != monitorScreenIds
        self.monitorScreenIds = newScreenIds
        // A changed mapping means existing strips may now belong on a different
        // screen; re-run the sync so they are repositioned. Skipped during the
        // very first load (no windows/monitors yet), where `.loaded` drives sync.
        if changed && isLoaded {
            emit(.monitorsChanged)
        }
    }

    public func stop() {
        subscribeTask?.cancel()
        subscribeTask = nil
        terminationTask?.cancel()
        terminationTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// Windows we've optimistically closed (their tiles are already gone) but which
    /// AeroSpace may still list for a moment while the app tears the window down. Reloads
    /// suppress these so a tile can't flicker back before the close completes.
    private var pendingCloseIds: Set<Int> = []

    // MARK: - Actions

    public func dispatch(_ action: AeroControlAction) async {
        // Arm close-suppression synchronously with the optimistic tile removal below, so a
        // reload already in flight can't land between the removal and the effect hop and
        // flicker the tile back.
        if case .closeWindow(let windowId) = action {
            pendingCloseIds.insert(windowId)
        }
        apply(.action(action))
    }

    // MARK: - Internal



    private func startSubscribeListener() {
        guard subscribeTask == nil else { return }
        subscribeTask = Task.detached(priority: .utility) { [weak self] in
            while let self, !Task.isCancelled {
                // A finished stream (AeroSpace exited) or a thrown transport error both
                // mean the subscription dropped; reconnect after a short backoff either way.
                do {
                    let stream = self.runner.subscribe(AerospaceCommand.subscribe())
                    for try await line in stream {
                        if let event = AerospaceEvent.parse(line) {
                            await self.handleEvent(event)
                        }
                    }
                } catch {}
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startTerminationListener() {
        guard terminationTask == nil else { return }
        terminationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.nativeSystem.appTerminations() {
                guard !Task.isCancelled else { return }
                self.handleEvent(.appTerminated)
            }
        }
    }

    private func apply(_ input: OverviewInput, animated: Bool = true) {
        let (newState, effects) = Common.updateOverview(model, input)
        // Don't animate workspace-focus changes: the focus plate should snap to the
        // newly focused workspace instantly, not fade/scale across.
        let focusChanged = newState.focusedWorkspace != model.focusedWorkspace
        if animated && !focusChanged {
            withAnimation(.easeInOut(duration: 0.1)) {
                model = newState
            }
        } else {
            model = newState
        }
        // Execute effects outside animation transaction to avoid constraint loops
        DispatchQueue.main.async { [self] in
            self.executeEffects(effects)
        }
    }

    private func handleEvent(_ event: AerospaceEvent) {
        apply(.event(event))
        switch event {
        case .workspaceChanged(let workspace, _), .monitorChanged(let workspace, _):
            notifyWorkspaceFocused(workspace)
        default:
            break
        }
    }

    /// After a workspace gains focus, hand the focused workspace to listeners so
    /// they can react to its floating windows.
    private func notifyWorkspaceFocused(_ workspaceName: String) {
        guard let workspace = model.workspaces.first(where: { $0.name == workspaceName }) else { return }
        emit(.workspaceFocused(workspace))
    }

    private func executeEffects(_ effects: [OverviewEffect]) {
        for effect in effects {
            switch effect {
            case .windowRemoved(let id):
                icons.removeValue(forKey: id)
            case .loadIcons(let windows):
                var added: [Int: NSImage] = [:]
                for window in windows where icons[window.windowId] == nil {
                    added[window.windowId] = nativeSystem.appIcon(bundleId: window.bundleId)
                }
                if !added.isEmpty {
                    icons.merge(added) { _, new in new }
                }
            case .validateWindows:
                validateLiveWindows()
            case .refresh:
                requestRefresh()
            case .monitorsChanged:
                emit(.monitorsChanged)
            case .runAction(let action):
                runAction(action)
            }
        }
    }

    /// Executes a user action's aerospace CLI command and reconciles the strip against
    /// reality where an action has no dedicated event to observe.
    private func runAction(_ action: AeroControlAction) {
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.runner.run(AerospaceCommand.argv(for: action))
                // A close has no dedicated event. Keep suppressing the window until it is
                // actually gone (bounded), then resync. A real close drops the tile; an app
                // that kept the window open (e.g. an unsaved-changes prompt) reappears.
                if case .closeWindow(let windowId) = action {
                    for _ in 0..<13 {
                        if !self.nativeSystem.liveWindowIds().contains(windowId) { break }
                        try? await Task.sleep(for: .milliseconds(150))
                    }
                    self.pendingCloseIds.remove(windowId)
                    self.requestRefresh()
                }
            } catch {
                // The optimistic change already updated the model; on failure, stop any
                // close suppression and resync to the real state.
                if case .closeWindow(let windowId) = action {
                    self.pendingCloseIds.remove(windowId)
                }
                switch action {
                case .moveWindow, .closeWindow:
                    self.requestRefresh()
                default:
                    break
                }
            }
        }
    }

    private func validateLiveWindows() {
        let knownIds = Set(model.workspaces.flatMap(\.windows).map(\.windowId))
        guard !knownIds.isEmpty else { return }

        let liveIds = nativeSystem.liveWindowIds()
        let staleIds = knownIds.subtracting(liveIds)
        if !staleIds.isEmpty {
            apply(.windowsValidated(liveIds: liveIds))
        }
    }

    private var refreshInFlight = false
    private var needsRefresh = false

    /// Funnels every reload through a single in-flight load. A request while a load is
    /// already running just marks the state dirty; when that load finishes it re-runs
    /// once more. This keeps applies ordered — no out-of-order `.loaded` can overwrite
    /// newer event-driven state — and collapses an event burst's process storm into at
    /// most one in-flight load plus one trailing reload, without ever dropping the final
    /// reload the way a trailing debounce would.
    private func requestRefresh() {
        needsRefresh = true
        guard !refreshInFlight else { return }
        refreshInFlight = true
        refreshTask = Task { [weak self] in
            guard let self else { return }
            // Snapshot the windows we already show *before* the burst reloads. Dead-window
            // suppression only prunes these — a window that first appears during the burst is
            // trusted even if CGWindowList hasn't composited it yet (see suppressingDeadWindows).
            let knownAtStart = Set(self.model.workspaces.flatMap(\.windows).map(\.windowId))
            while self.needsRefresh {
                guard !Task.isCancelled else { break }
                self.needsRefresh = false
                guard let result = try? await loadOverview(using: self.runner) else { continue }
                self.apply(.loaded(self.suppressingPendingCloses(self.suppressingDeadWindows(result, knownIds: knownAtStart))))
                // A successful reload proves aerospace is reachable again; clear any
                // stale startup error so it doesn't stick after recovery.
                self.error = nil
            }
            self.refreshInFlight = false
        }
    }

    /// Drops windows AeroSpace still lists but that the window server no longer knows.
    /// CGWindowList is authoritative and updates the instant a window closes, whereas
    /// AeroSpace's list briefly lags a close and emits no event when it catches up — so a
    /// reload racing that lag would keep a dead tile forever. Skipped when the live set is
    /// empty (an API failure) so a transient hiccup can never prune the whole overview.
    ///
    /// Only windows already on screen before this reload burst (`knownIds`) are eligible for
    /// pruning. CGWindowList lags the *other* way on open — a just-detected window is in
    /// AeroSpace before macOS composites it into the window server — so a brand-new window is
    /// trusted even when it isn't live yet. Otherwise the one-shot `window-detected`/`focus-
    /// changed` refresh would suppress it with no further event to re-trigger a reload, and the
    /// tile would stay missing until an unrelated event (e.g. a workspace switch) forced one.
    private func suppressingDeadWindows(_ result: OverviewResult, knownIds: Set<Int>) -> OverviewResult {
        let liveIds = nativeSystem.liveWindowIds()
        guard !liveIds.isEmpty else { return result }
        let workspaces = result.workspaces.map { ws -> WorkspaceInfo in
            var ws = ws
            ws.windows = ws.windows.filter { liveIds.contains($0.windowId) || !knownIds.contains($0.windowId) }
            return ws
        }
        return OverviewResult(workspaces: workspaces)
    }

    /// Drops any optimistically-closed windows AeroSpace still lists, so a reload during
    /// the close grace period can't resurrect a tile we've already removed.
    private func suppressingPendingCloses(_ result: OverviewResult) -> OverviewResult {
        guard !pendingCloseIds.isEmpty else { return result }
        let workspaces = result.workspaces.map { ws -> WorkspaceInfo in
            var ws = ws
            ws.windows = ws.windows.filter { !pendingCloseIds.contains($0.windowId) }
            return ws
        }
        return OverviewResult(workspaces: workspaces)
    }
}
