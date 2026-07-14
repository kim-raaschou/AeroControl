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

    // MARK: - Actions

    public func dispatch(_ action: AeroControlAction) async {
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
        // The manually-hosted NSHostingView doesn't auto-observe @Observable model
        // changes, so the host must rebuild the panel when the rendered model changes.
        // Compare before assigning; monitor-set changes are handled by the
        // `.monitorsChanged` effect (a full re-sync), so only signal same-monitor
        // content changes here — and skip no-op reloads to avoid needless rebuilds.
        let contentChanged = newState != model
        if animated && !focusChanged {
            withAnimation(.easeInOut(duration: 0.1)) {
                model = newState
            }
        } else {
            model = newState
        }
        if contentChanged {
            emit(.contentChanged)
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
            case .refresh:
                requestRefresh()
            case .monitorsChanged:
                emit(.monitorsChanged)
            case .runAction(let action):
                runAction(action)
            }
        }
    }

    /// Executes a user action's aerospace CLI command, then reconciles the strip against
    /// reality — a move or close has no dedicated event to observe, so reload once the
    /// command returns (on success or failure) and let AeroSpace's list be the truth.
    private func runAction(_ action: AeroControlAction) {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.runner.run(AerospaceCommand.argv(for: action))
            switch action {
            case .moveWindow, .closeWindow:
                self.requestRefresh()
            default:
                break
            }
        }
    }

    private var refreshGeneration = 0

    /// Mirrors AeroSpace: every change re-reads its full state and applies it verbatim.
    /// A generation stamp guarantees only the newest reload wins, so a burst collapses to a
    /// single apply (the latest truth) without any single-flight gate that could stick and
    /// freeze the mirror. AeroSpace is the source of truth — no bookkeeping, no ordering
    /// tricks beyond "newest wins".
    private func requestRefresh() {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            guard let result = try? await loadOverview(using: self.runner) else { return }
            // A newer refresh superseded us while this load was in flight; drop the stale
            // result so only the latest state is applied (ordered, no UI churn).
            guard generation == self.refreshGeneration else { return }
            // A successful reload also proves aerospace is reachable, so clear any stale
            // startup error so it doesn't stick after recovery.
            self.apply(.loaded(result))
            self.error = nil
        }
    }
}
