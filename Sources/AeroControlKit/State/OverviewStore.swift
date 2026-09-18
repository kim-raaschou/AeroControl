import AppKit
import SwiftUI
import Common

@MainActor @Observable
public class OverviewStore {
    public private(set) var model = OverviewModel()

    let runner: AerospaceProcessRunner
    let nativeSystem: NativeApiBridge
    private(set) var icons: [Int: NSImage] = [:]
    /// Window previews, captured when the overview is summoned and dropped when it hides.
    public private(set) var previews: [Int: NSImage] = [:]
    public private(set) var error: String?
    /// The window the mouse is over, if any. Cmd-Q acts on it, the way Mission Control's
    /// does: the overview is a place you point at windows, so pointing is the selection.
    public var hoveredWindowId: Int?

    /// What the user has typed into the overview. UI state that drives no AeroSpace work, so
    /// it lives here beside `hoveredWindowId` rather than in the model: the reducer's contract
    /// is AeroSpace state in, AeroSpace work out, its inbox is an AsyncStream (a keystroke
    /// would be applied a hop late, possibly behind a reload), and `apply` animates every model
    /// change — the grid would jump on every letter.
    public var filter: String = "" { didSet { selection = 0 } }

    /// The match the ring is on and Enter picks, as an index into `filterMatches`. Back to
    /// the first on every keystroke: the list under it has just changed.
    public var selection: Int = 0

    /// Every window the query picks out, in the order the grid draws them. The grid, the ring
    /// and Enter all read this one list, so what the ring is on is what Enter focuses.
    public var filterMatches: [ParsedWindow] { model.matching(filter) }

    /// The window wearing the ring: the selected match while the filter has any, AeroSpace's
    /// focused window otherwise — so on the map, and on a miss, the ring means what it always
    /// did.
    public var ringWindowId: Int? {
        filterMatches.selected(selection)?.window.windowId ?? model.focusedWindowId
    }

    private let inbox: AsyncStream<OverviewInput>
    private let inboxContinuation: AsyncStream<OverviewInput>.Continuation

    private var inboxTask: Task<Void, Never>?
    private var subscribeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    /// Bumped by every capture and clear so a stale capture cannot overwrite newer state.
    private var captureGeneration = 0

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.runner = runner
        self.nativeSystem = nativeSystem
        (inbox, inboxContinuation) = AsyncStream.makeStream()
    }

    public func send(_ input: OverviewInput) {
        inboxContinuation.yield(input)
    }

    public func start() {
        startInbox()
    }

    /// Reads AeroSpace's whole state and applies it. The overview is a one shot: the host
    /// awaits this at summon, so what is drawn is what AeroSpace says right now.
    public func reload() async {
        do {
            let result = try await loadOverview(using: runner)
            apply(.loaded(result), animated: false)
            error = nil
        } catch {
            self.error = "Load error: \(error.localizedDescription)"
        }
    }

    /// While the overview is on screen it follows AeroSpace live; while it is hidden there
    /// is nothing to keep in sync, so the subscription is scoped to visibility rather than
    /// to the process. Nothing reads the model between summons.
    public func startFollowingAerospace() {
        guard subscribeTask == nil else { return }
        startSubscribeListener()
    }

    public func stopFollowingAerospace() {
        subscribeTask?.cancel()
        subscribeTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func stop() {
        inboxContinuation.finish()
        inboxTask?.cancel()
        inboxTask = nil
        subscribeTask?.cancel()
        subscribeTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        captureGeneration += 1
    }

    // MARK: Window previews

    /// True when macOS lets us capture windows; decides the tile layout up front so the
    /// overview does not jump when the images arrive.
    public var previewsAvailable: Bool { nativeSystem.canCapturePreviews }

    public func requestPreviewAccess() { nativeSystem.requestPreviewAccess() }

    /// Capture previews for every window currently in the model and store them. Returns
    /// when they are in, so the caller can reveal the overview with the images already
    /// there. A `clearPreviews()` in the meantime discards the result.
    public func capturePreviews(maxSize: CGSize) async {
        let ids = model.workspaces.flatMap(\.windows).map(\.windowId)
        captureGeneration += 1
        let generation = captureGeneration
        let images = await nativeSystem.windowPreviews(windowIds: ids, maxSize: maxSize)
        guard generation == captureGeneration else { return }
        previews = images
    }

    public func clearPreviews() {
        captureGeneration += 1
        previews = [:]
    }

    public func dispatch(_ action: AeroControlAction) async {
        send(.action(action))
    }

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
            var reconnecting = false
            while let self, !Task.isCancelled {
                // Everything that happened while the stream was down is lost — and we pass
                // `--no-send-initial`, so AeroSpace will not replay it either. Read once
                // after a reconnect so a dropped stream costs latency, never correctness.
                if reconnecting { await self.reload() }
                do {
                    let stream = self.runner.subscribe(AerospaceCommand.subscribe())
                    for try await line in stream {
                        if let event = AerospaceEvent.parse(line) {
                            await self.send(.event(event))
                        }
                    }
                } catch {}
                guard !Task.isCancelled else { return }
                reconnecting = true
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func apply(_ input: OverviewInput, animated: Bool = true) {
        let (newState, effects) = Common.updateOverview(model, input)
        let focusChanged = newState.focusedWorkspace != model.focusedWorkspace
        if newState != model {
            if animated && !focusChanged {
                withAnimation(.easeInOut(duration: 0.1)) {
                    model = newState
                }
            } else {
                model = newState
            }
        }
        DispatchQueue.main.async { [self] in
            self.executeEffects(effects)
        }
    }

    private func executeEffects(_ effects: [OverviewEffect]) {
        for effect in effects {
            switch effect {
            case .windowRemoved(let id):
                icons.removeValue(forKey: id)
                previews.removeValue(forKey: id)
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
            case .runAction(let action):
                runAction(action)
            case .runSequence(let actions):
                runSequence(actions)
            }
        }
    }

    private func runAction(_ action: AeroControlAction) {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.runner.run(AerospaceCommand.argv(for: action))
            switch action {
            case .moveWindow, .moveWindowQuietly, .closeWindow:
                self.requestRefresh()
            default:
                break
            }
        }
    }

    /// Runs actions strictly one after another (a merge must keep the tiling order and
    /// switch focus last), then reloads once. A failing step does not stop the rest:
    /// AeroSpace stays the source of truth and the reload shows what actually happened.
    private func runSequence(_ actions: [AeroControlAction]) {
        Task { [weak self] in
            guard let self else { return }
            for action in actions {
                _ = try? await self.runner.run(AerospaceCommand.argv(for: action))
            }
            self.requestRefresh()
        }
    }

    private var refreshGeneration = 0

    private func requestRefresh() {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            guard let result = try? await loadOverview(using: self.runner) else { return }
            guard generation == self.refreshGeneration else { return }
            self.error = nil
            self.send(.loaded(result))
        }
    }
}
