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
    public private(set) var error: String?

    /// Host reactions the store can't perform itself because it owns no windows. The
    /// host (or a test) sets these; the store calls them directly instead of fanning a
    /// separate output stream out to a single consumer.
    ///   • onLoaded — the initial load finished; reveal / show an error fallback.
    ///   • onMonitorsChanged — the monitor set (derived from workspaces) changed;
    ///     re-sync the window so it re-clamps to the active screen's current extent.
    public var onLoaded: (@MainActor () -> Void)?
    public var onMonitorsChanged: (@MainActor () -> Void)?

    /// Single ingress. Every live driver — the AeroSpace subscribe stream, the native
    /// app-termination bridge, user actions, and reload results — funnels its input into
    /// this inbox, and one serialized consumer (`startInbox`) applies them in arrival
    /// order. This gives AeroControl exactly one entrance, so ordering across sources is
    /// deterministic and an integration test can drive the whole store from one channel.
    private let inbox: AsyncStream<OverviewInput>
    private let inboxContinuation: AsyncStream<OverviewInput>.Continuation

    private var inboxTask: Task<Void, Never>?
    private var subscribeTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private var windowCloseTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.runner = runner
        self.nativeSystem = nativeSystem
        (inbox, inboxContinuation) = AsyncStream.makeStream()
    }

    /// Funnels one input into the single inbox. Callers never touch `apply` directly;
    /// the serialized consumer owns application order.
    public func send(_ input: OverviewInput) {
        inboxContinuation.yield(input)
    }

    public func start() async {
        await initialLoad()
        startInbox()
        startSubscribeListener()
        startTerminationListener()
        startWindowCloseListener()
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
                self.onLoaded?()
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
                apply(.loaded(result), animated: false)
                self.error = nil
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
    }

    public func stop() {
        inboxContinuation.finish()
        inboxTask?.cancel()
        inboxTask = nil
        subscribeTask?.cancel()
        subscribeTask = nil
        terminationTask?.cancel()
        terminationTask = nil
        windowCloseTask?.cancel()
        windowCloseTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - Actions

    public func dispatch(_ action: AeroControlAction) async {
        send(.action(action))
    }

    // MARK: - Internal

    /// The single serialized consumer: drains the inbox in arrival order and applies each
    /// input through the pure reducer. All outputs (including focus-follow) flow from the
    /// reducer's effects, so the consumer has no per-input special-casing.
    private func startInbox() {
        guard inboxTask == nil else { return }
        inboxTask = Task { [weak self] in
            guard let self else { return }
            for await input in self.inbox {
                if Task.isCancelled { return }
                self.apply(input)
            }
        }
    }

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
                            await self.send(.event(event))
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
                self.send(.event(.localWindowClosed))
                // AeroSpace may not have reaped the closed window yet when the OS fires
                // the app-termination, so a single reconcile can race ahead of the truth.
                // Fire one bounded, delayed retry to catch that; not polling — one shot.
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.send(.event(.localWindowClosed))
                }
            }
        }
    }

    /// The permission-free close doorbell: a background window closed with the mouse
    /// produces no AeroSpace event, so each global left-mouse-up triggers a reconcile.
    /// Newest-wins `requestRefresh` collapses bursts, so rapid clicks cost one reload.
    private func startWindowCloseListener() {
        guard windowCloseTask == nil else { return }
        windowCloseTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.nativeSystem.windowCloseSignals() {
                guard !Task.isCancelled else { return }
                self.send(.event(.localWindowClosed))
            }
        }
    }

    private func apply(_ input: OverviewInput, animated: Bool = true) {
        let (newState, effects) = Common.updateOverview(model, input)
        // Don't animate workspace-focus changes: the focus plate should snap to the
        // newly focused workspace instantly, not fade/scale across.
        let focusChanged = newState.focusedWorkspace != model.focusedWorkspace
        // The hosted panel is `@Bindable` on this `@Observable` store and its
        // `NSHostingView` auto-observes `model`, so re-rendering is automatic — no
        // explicit rebuild output is needed. `@Observable` invalidates on *assignment*,
        // not inequality, so guard the assignment: skip no-op reloads (mirroring
        // AeroSpace on every event frequently re-reads identical state) to avoid needless
        // re-renders / mid-hover resets. Monitor-set changes are handled separately by
        // the `.monitorsChanged` effect (a full window re-sync).
        if newState != model {
            if animated && !focusChanged {
                withAnimation(.easeInOut(duration: 0.1)) {
                    model = newState
                }
            } else {
                model = newState
            }
        }
        // Execute effects outside animation transaction to avoid constraint loops
        DispatchQueue.main.async { [self] in
            self.executeEffects(effects)
        }
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
                onMonitorsChanged?()
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
            self.error = nil
            // Re-enter through the single inbox rather than applying directly, so reload
            // results share the one ordered ingress with events and actions.
            self.send(.loaded(result))
        }
    }
}
