import AppKit
import SwiftUI
import Common

@MainActor @Observable
public class OverviewStore {
    public private(set) var model = OverviewModel() { didSet { filterMatches = model.matching(filter); cursor = model.cursor(for: filterMatches) } }

    let runner: AerospaceProcessRunner
    let nativeSystem: NativeApiBridge
    private(set) var icons: [Int: NSImage] = [:]
    /// Window previews, captured when the overview is summoned and dropped when it hides.
    /// They land one by one into a grid that is already on screen.
    public private(set) var previews: [Int: NSImage] = [:]
    /// Each window's on-screen size, known before any picture is: the grid takes its
    /// shape from these, so pictures landing later change nothing but the pictures.
    public private(set) var previewSizes: [Int: CGSize] = [:]
    public private(set) var error: String?
    /// The window the mouse is over, if any. Cmd-Q acts on it, the way Mission Control's
    /// does: the overview is a place you point at windows, so pointing is the selection.
    public var hoveredWindowId: Int?

    /// What the user has typed into the overview. UI state that drives no AeroSpace work, so
    /// it lives here beside `hoveredWindowId` rather than in the model: the reducer's contract
    /// is AeroSpace state in, AeroSpace work out, its inbox is an AsyncStream (a keystroke
    /// would be applied a hop late, possibly behind a reload), and `apply` animates every model
    /// change — the grid would jump on every letter.
    public var filter: String = "" { didSet { selection = nil; filterMatches = model.matching(filter); cursor = model.cursor(for: filterMatches) } }

    /// The window the ring is on and Enter picks, as an index into `cursor`; nil until a
    /// key moves it, meaning the first match while filtering and AeroSpace's focused window
    /// on the map. Back to nil on every keystroke: the list under it has just changed.
    public var selection: Int?

    /// What the ring walks: the matches while a query has some, every window in grid order
    /// otherwise — the map is navigable too.
    public private(set) var cursor: [ParsedWindow] = []

    /// Where the ring stands before any key has moved it.
    private var restingSelection: Int {
        filterMatches.isEmpty ? (cursor.firstIndex { $0.window.windowId == model.focusedWindowId } ?? 0) : 0
    }

    /// What the panel drew, reported as it lays out, because only it knows a card's width
    /// and place: how many tile columns each card has (by workspace) and which cards share
    /// a row. What ↑/↓ steer by.
    public var columns: [String: Int] = [:]
    public var cardRows: [[String]] = []

    /// Every window the query picks out, in the order the grid draws them. The grid, the ring
    /// and Enter all read this one list, so what the ring is on is what Enter focuses. Derived
    /// when the query or the model changes, not on read: every tile asks for the ring, and a
    /// computed property here was a scan of every title per tile per pass.
    public private(set) var filterMatches: [ParsedWindow] = []

    /// The window wearing the ring: the selected match while the filter has any, AeroSpace's
    /// focused window otherwise — so on the map, and on a miss, the ring means what it always
    /// did.
    public var ringWindowId: Int? {
        guard selection != nil || !filterMatches.isEmpty else { return model.focusedWindowId }
        return cursor.selected(selection ?? restingSelection)?.window.windowId ?? model.focusedWindowId
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
        previewsAvailable = nativeSystem.canCapturePreviews
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
    /// overview does not jump when the images arrive. Read from the system once per reload
    /// and after a request, not on access: every card asked on every body, and the answer
    /// is a TCC round-trip.
    public private(set) var previewsAvailable = false

    /// Warms the capture path before `reload()`, so the system's window enumeration and
    /// AeroSpace's answer arrive together rather than one after the other.
    public func prepareCapture() { nativeSystem.prepareCapture() }

    public func requestPreviewAccess() {
        nativeSystem.requestPreviewAccess()
        previewsAvailable = nativeSystem.canCapturePreviews
    }

    private var windowIds: [Int] { model.workspaces.flatMap(\.windows).map(\.windowId) }

    /// Reads every window's size — cheap, the enumeration was started with `prepareCapture`
    /// — so the overview can be revealed with its final shape before a picture is taken.
    public func measurePreviews() async {
        captureGeneration += 1
        let generation = captureGeneration
        let sizes = await nativeSystem.previewSizes(windowIds: windowIds)
        guard generation == captureGeneration else { return }
        previewSizes = sizes
    }

    /// True while pictures are still landing: a tile without one shows its place, not an
    /// icon. Once capture is over, a tile still without a picture shows the icon.
    public private(set) var capturing = false

    /// Captures a preview of every window in the model, each stored the moment it lands.
    /// Returns when all are in. A `clearPreviews()` in the meantime discards the rest.
    public func capturePreviews(maxSize: CGSize) async {
        let generation = captureGeneration
        capturing = true
        await nativeSystem.windowPreviews(windowIds: windowIds, maxSize: maxSize) { [weak self] id, image in
            guard let self, generation == self.captureGeneration else { return }
            self.previews[id] = image
        }
        if generation == captureGeneration { capturing = false }
    }

    public func clearPreviews() {
        captureGeneration += 1
        capturing = false
        previews = [:]
        previewSizes = [:]
    }

    /// The "other windows of this app" summon: the query is the focused window's app name,
    /// and the ring starts on the window *after* the focused one, so Enter alone switches
    /// to the next instance — Cmd-` with pictures — and Tab walks on from there. Text, not
    /// bundle id, on purpose: the pill shows a query you can keep typing into.
    ///
    /// False, and the filter untouched, when there is nothing to choose between — one
    /// window or none. The summon is a picker, and a picker with one option is a flash of
    /// screen for nothing.
    public func filterToFocusedApp() -> Bool {
        guard let name = model.focusedAppName else { return false }
        let matches = model.matching(name)
        guard matches.count > 1,
              let at = matches.firstIndex(where: { $0.window.windowId == model.focusedWindowId }) else { return false }
        filter = name
        selection = (at + 1) % matches.count
        return true
    }

    /// Type-to-filter. A keystroke the filter has a use for is applied here — the query and
    /// the ring are the store's — and the caller learns what became of it: `.none` is not
    /// ours, `.focus` is a pick the caller carries out, since focusing means hiding and the
    /// window is the caller's.
    public func handle(_ key: FilterKey) -> FilterKeyAction {
        let action = filterKeyAction(query: filter, matches: cursor, selection: selection ?? restingSelection,
                                     columns: columns, cardRows: cardRows, key: key)
        switch action {
        case .setQuery(let query): filter = query
        case .select(let index): selection = index
        case .none, .focus: break
        }
        return action
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
            // Not animated: the grid animates its own reflow, and a second 0.1 s animation
            // restarted on every event fought it.
            self.apply(.loaded(result), animated: false)
        }
    }
}
