import AppKit
import SwiftUI
import Common

@MainActor @Observable
public class OverviewStore {
    public private(set) var model = OverviewModel() {
        didSet {
            if var strip {
                let before = oldValue.windowsInGridOrder.filter { $0.window.bundleId == strip.bundleId }.map(\.window.windowId)
                let lastIndex = strip.marked.flatMap { before.firstIndex(of: $0) } ?? 0
                strip.marked = AppStripModel.keepSelection(strip.marked, lastIndex: lastIndex, ids: stripWindows.map(\.window.windowId))
                self.strip = strip
            }
            filterMatches = model.matching(filter)
            cursor = model.cursor(for: filterMatches)
            for window in model.workspaces.lazy.flatMap(\.windows) where icons[window.bundleId] == nil {
                icons[window.bundleId] = nativeSystem.appIcon(bundleId: window.bundleId)
            }
        }
    }

    /// Apps macOS has hidden, read with every load: their tiles are dimmed.
    public private(set) var hiddenBundleIds: Set<String> = []

    /// App icons by bundle id, for the badge in a picture's corner: the one thing a picture
    /// does not say about a window is which app it is. Loaded once per app, kept for good.
    public private(set) var icons: [String: NSImage] = [:]

    let runner: AerospaceProcessRunner
    let nativeSystem: NativeApiBridge
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
    public var filter: String = "" {
        didSet {
            selection = nil
            filterMatches = model.matching(filter)
            cursor = model.cursor(for: filterMatches)
            refreshFilteredPictures()
        }
    }

    /// The window the ring is on and Enter picks, as an index into `cursor`; nil until a
    /// key moves it, meaning the first match while filtering and AeroSpace's focused window
    /// on the map. Back to nil on every keystroke: the list under it has just changed.
    public var selection: Int?

    /// How the overview is drawn this visit: the map of every workspace, or the strip — one
    /// row of one app's windows, like macOS's own switcher. Set by the host per summon.
    public enum Presentation: Sendable { case map, strip }
    public var presentation: Presentation = .map {
        didSet { if presentation == .map { strip = nil } }
    }

    /// The strip this visit: whose windows, the window you came from, and the marking. Its own
    /// state, not a query: the app is named by bundle id, so a window of another app whose
    /// title happens to name this one is not in it, and nothing typed narrows it.
    public struct Strip: Equatable, Sendable {
        public let bundleId: String
        public let origin: Int?
        public internal(set) var marked: Int? {
            didSet { if !pointed { centre = marked } }
        }
        /// The window the carousel centres on: the marking, as keys move it. Pointing marks
        /// without moving it, or the row would slide another window under a hand that had not
        /// moved (krn.overview: "Keys move the centre; the pointer does not").
        public internal(set) var centre: Int?
        /// How many times the keys have taken the ring round past its last card, less the times
        /// back past its first: what keeps the carousel turning one way instead of jumping back.
        public internal(set) var turns = 0
        var pointed = false

        init(bundleId: String, origin: Int?, marked: Int?) {
            self.bundleId = bundleId; self.origin = origin; self.marked = marked; self.centre = marked
        }
    }
    public private(set) var strip: Strip?

    /// The strip's windows, in the order the map draws them.
    public var stripWindows: [ParsedWindow] {
        guard let strip else { return [] }
        return model.windowsInGridOrder.filter { $0.window.bundleId == strip.bundleId }
    }

    /// The workspaces that hold the strip's app, whole: a card mirrors all of a workspace, the
    /// other apps' windows drawn grey behind the app's, not only the app's windows.
    public var stripWorkspaces: [WorkspaceInfo] {
        guard let strip else { return [] }
        return model.workspaces.filter { $0.windows.contains { $0.bundleId == strip.bundleId } }
    }

    /// The summon key again while the strip is up: the marking moves on, as Cmd-` does.
    public func stepStrip(_ direction: Int = 1) {
        guard var strip else { return }
        let ids = stripWindows.map(\.window.windowId)
        let at = AppStripModel.stepPickable(strip.marked.flatMap { ids.firstIndex(of: $0) } ?? -1,
                                            pickable: ids.map { _ in true }, direction: direction)
        let card = { (id: Int?) in id.flatMap { id in self.stripWorkspaces.firstIndex { $0.windows.contains { $0.windowId == id } } } }
        let from = card(strip.centre)
        strip.marked = at >= 0 ? ids[at] : strip.marked
        if let from, let to = card(strip.centre) {
            if direction > 0, to < from { strip.turns += 1 }
            if direction < 0, to > from { strip.turns -= 1 }
        }
        self.strip = strip
    }

    /// Pointing marks, as in krn.overview's strip; a window that is not the app's is ignored.
    public func markStrip(_ windowId: Int) {
        guard var strip, stripWindows.contains(where: { $0.window.windowId == windowId }) else { return }
        strip.pointed = true
        strip.marked = windowId
        strip.pointed = false
        self.strip = strip
    }

    /// Where the mouse was when the strip last heard from it, in screen points.
    private var stripPointer: CGPoint?

    /// The mouse's place as the strip opens, so a card that slides under it is not pointed at.
    public func notePointer(_ location: CGPoint) { stripPointer = location }

    /// The pointer entered a window: it marks only if the mouse moved. A hover also fires when
    /// the carousel turns, or the strip opens, under a hand that is still, and that must not
    /// take the marking away from the keys.
    public func pointStrip(_ windowId: Int, at location: CGPoint) {
        guard location != stripPointer else { return }
        stripPointer = location
        markStrip(windowId)
    }

    /// A key that puts the marking on a window: the centre goes with it.
    private func selectStrip(_ windowId: Int) {
        guard var strip else { return }
        strip.marked = windowId
        self.strip = strip
    }

    /// What the ring walks: the matches while a query has some, every window in grid order
    /// otherwise — the map is navigable too.
    public private(set) var cursor: [ParsedWindow] = []

    /// Where the ring stands before any key has moved it.
    private var restingSelection: Int {
        filterMatches.isEmpty ? (cursor.firstIndex { $0.window.windowId == model.focusedWindowId } ?? 0) : 0
    }

    /// What the panel drew, reported as it lays out, because only it knows a card's width
    /// and place: each card's tile rows (window ids, by workspace) and which cards share a
    /// row. What ↑/↓ steer by.
    public var tileRows: [String: [[Int]]] = [:]
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
        if let strip { return strip.marked }
        guard selection != nil || !filterMatches.isEmpty else { return model.focusedWindowId }
        return cursor.selected(selection ?? restingSelection)?.window.windowId ?? model.focusedWindowId
    }

    private let inbox: AsyncStream<OverviewInput>
    private let inboxContinuation: AsyncStream<OverviewInput>.Continuation

    private var inboxTask: Task<Void, Never>?
    private var subscribeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    /// Whether this AeroSpace lists where its layout put each window; learned by the first
    /// load that gets an answer, and kept for the process. See `LayoutRects`.
    public private(set) var layoutRects: LayoutRects = .unknown

    /// The pictures are shown together rather than one by one as they land: held back until
    /// the capture is in, or `revealAfter` has passed, then faded in at once.
    public private(set) var revealsPictures = false
    static let revealAfter: Duration = .milliseconds(120)
    private var revealTask: Task<Void, Never>?
    /// Pictures taken but not yet in `previews`: they land together, at the reveal, and after
    /// it at most once a frame.
    private var arrivingPictures: [Int: NSImage] = [:]
    private var landingTask: Task<Void, Never>?

    private func landPictures() {
        landingTask?.cancel()
        landingTask = nil
        guard !arrivingPictures.isEmpty else { return }
        previews.merge(arrivingPictures) { $1 }
        arrivingPictures = [:]
    }

    private func landPicturesSoon() {
        guard landingTask == nil else { return }
        landingTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { return }
            self?.landPictures()
        }
    }
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
            let result = try await loadOverview(using: runner, layoutRects: layoutRects)
            layoutRects = result.layoutRects
            apply(.loaded(result))
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

    /// The box the pictures were taken to fit, kept for re-taking a few of them.
    private var captureSize: CGSize?
    private var refreshPicturesTask: Task<Void, Never>?

    /// Captures a preview of every window drawn — the model's, or in the strip every window of
    /// its workspaces, once, at the strip's size — each stored the moment it lands. Returns when
    /// all are in. A `clearPreviews()` in the meantime discards the rest.
    public func capturePreviews(maxSize: CGSize) async {
        let generation = captureGeneration
        captureSize = maxSize
        revealTask?.cancel()
        revealTask = Task { [weak self] in
            try? await Task.sleep(for: Self.revealAfter)
            guard !Task.isCancelled, let self, generation == self.captureGeneration else { return }
            self.revealsPictures = true
            self.landPictures()
        }
        let ids = strip == nil ? windowIds : stripWorkspaces.flatMap { $0.windows.map(\.windowId) }
        // Held, not stored: every picture stored redraws the whole overview, and on the main
        // thread that drew the map once per window and kept the captures still in flight from
        // landing — 19 windows came in batches, the last 230 ms after it was taken.
        await nativeSystem.windowPreviews(windowIds: ids, maxSize: maxSize) { [weak self] id, image in
            guard let self, generation == self.captureGeneration else { return }
            self.arrivingPictures[id] = image
            if self.revealsPictures { self.landPicturesSoon() }
        }
        if generation == captureGeneration { revealsPictures = true; landPictures() }
        // A summon can arrive already filtered — the app picker — before any size was known
        // for the re-take to work from; the pictures are in now, so it starts here.
        refreshFilteredPictures()
    }

    /// A filtered tile is three to four times the size of one on the map, so the picture
    /// taken for the map is a blur there; a few are re-taken this much larger.
    private static let detailScale: CGFloat = 3

    /// Once a query has narrowed the grid to a few windows and the keystrokes have settled
    /// (150 ms), their pictures are re-taken — a handful of captures, at the size the
    /// filtered tiles are drawn — so what you are choosing between is current and sharp
    /// instead of the map's small picture from summon, scaled up. Once, not on a clock:
    /// the overview is a picture, not a screen share.
    private func refreshFilteredPictures() {
        refreshPicturesTask?.cancel()
        refreshPicturesTask = nil
        guard !filterMatches.isEmpty, let size = captureSize else { return }
        let generation = captureGeneration
        let detail = CGSize(width: size.width * Self.detailScale, height: size.height * Self.detailScale)
        refreshPicturesTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, generation == self.captureGeneration else { return }
            let ids = self.filterMatches.map(\.window.windowId)
            await self.nativeSystem.windowPreviews(windowIds: ids, maxSize: detail) { [weak self] id, image in
                guard let self, generation == self.captureGeneration else { return }
                self.previews[id] = image
            }
        }
    }

    public func clearPreviews() {
        captureGeneration += 1
        revealTask?.cancel()
        landingTask?.cancel()
        landingTask = nil
        arrivingPictures = [:]
        revealsPictures = false
        refreshPicturesTask?.cancel()
        refreshPicturesTask = nil
        captureSize = nil
        previews = [:]
        previewSizes = [:]
        PictureResampler.forget()
    }

    /// What an app summon comes to.
    public enum AppSummon: Equatable, Sendable {
        /// Start the app, or bring it forward if it runs; its windows are macOS's to order.
        case launch
        /// One window is the answer: focus it, and show nothing.
        case focus(windowId: Int)
        /// Windows to choose between: the filter and the ring are set; show the strip.
        case pick
        /// Nothing to do: no app named, and no window focused to name one.
        case none
    }

    /// One key on an app, `aerocontrol://windows?app=<bundle id>` — or, with no bundle id,
    /// on the app of the focused window, `aerocontrol://windows`: the same link, the
    /// focused app filled in. The count is free; the model was just read, so the key does
    /// the right thing whatever the app's state:
    ///
    /// - none: start it; one: focus it;
    /// - two, and you are in one of them: the other — a toggle needs no picker;
    /// - more, or coming from elsewhere: the strip, the marking on the window after the
    ///   focused one, so Enter alone is Cmd-` with pictures.
    ///
    /// The first two lines are the link's own and hold with the strip off. The rest are the
    /// strip's: with it off the key is a passthrough — it brings the app forward, and macOS
    /// decides which window is in front, which for the app you are in changes nothing.
    public func summonApp(bundleId named: String?, picker: Bool) -> AppSummon {
        guard let bundleId = named ?? model.focusedWindow?.bundleId else { return .none }
        let windows = model.windowsInGridOrder.map(\.window).filter { $0.bundleId == bundleId }
        let focusedAt = windows.firstIndex { $0.windowId == model.focusedWindowId }
        switch windows.count {
        case 0: return .launch
        case 1: return .focus(windowId: windows[0].windowId)
        default: break
        }
        guard picker else { return .launch }
        if windows.count == 2, let focusedAt { return .focus(windowId: windows[1 - focusedAt].windowId) }
        let origin = focusedAt.map { _ in model.focusedWindowId }
        strip = Strip(bundleId: bundleId, origin: origin, marked: AppStripModel.start(origin: origin, ids: windows.map(\.windowId)))
        return .pick
    }

    /// Type-to-filter. A keystroke the filter has a use for is applied here — the query and
    /// the ring are the store's — and the caller learns what became of it: `.none` is not
    /// ours, `.focus` is a pick the caller carries out, since focusing means hiding and the
    /// window is the caller's.
    public func handle(_ key: FilterKey) -> FilterKeyAction {
        if let strip { return handleStrip(key, strip) }
        let action = filterKeyAction(query: filter, matches: cursor, selection: selection ?? restingSelection,
                                     tileRows: tileRows, cardRows: cardRows, key: key)
        switch action {
        case .setQuery(let query): filter = query
        case .select(let index): selection = index
        case .none, .focus, .handled: break
        }
        return action
    }

    /// A key in the strip, by its own rules (`AppStripModel.action`): steps and Home/End move the
    /// marking, a key or Enter picks, Escape is the window's to close with; anything else is
    /// swallowed, since there is no typing in the strip.
    private func handleStrip(_ key: FilterKey, _ strip: Strip) -> FilterKeyAction {
        let ids = stripWindows.map(\.window.windowId)
        switch AppStripModel.action(for: key, ids: ids, pickable: ids.map { _ in true }, marked: strip.marked) {
        case .step(let direction): stepStrip(direction)
        case .select(let id): selectStrip(id)
        case .commit(let id): return .focus(windowId: id)
        case .cancel: return .none
        case .none: break
        }
        return .handled
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

    /// The grid animates its own reflow; the model changes in one step.
    private func apply(_ input: OverviewInput) {
        let (newState, effects) = Common.updateOverview(model, input)
        if newState != model { model = newState }
        if case .loaded = input { hiddenBundleIds = nativeSystem.hiddenBundleIds() }
        DispatchQueue.main.async { [self] in
            self.executeEffects(effects)
        }
    }

    private func executeEffects(_ effects: [OverviewEffect]) {
        for effect in effects {
            switch effect {
            case .windowRemoved(let id):
                previews.removeValue(forKey: id)
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
            guard let result = try? await loadOverview(using: self.runner, layoutRects: self.layoutRects) else { return }
            guard generation == self.refreshGeneration else { return }
            self.layoutRects = result.layoutRects
            self.error = nil
            self.apply(.loaded(result))
            await self.refreshChangedPictures()
        }
    }

    /// After AeroSpace has moved, closed or opened windows, the sizes measured at summon are stale
    /// for the windows that changed: the neighbours that widened into a hole, the window that
    /// landed in a new row. All sizes are read again, which is cheap, and only those windows get a
    /// new picture, plus any that appeared; a picture of a window whose size held is still true.
    /// Nothing while the overview is hidden: `clearPreviews` has dropped the capture size.
    private func refreshChangedPictures() async {
        guard let size = captureSize else { return }
        let generation = captureGeneration
        let before = previewSizes
        let ids = windowIds
        let sizes = await nativeSystem.previewSizes(windowIds: ids)
        guard generation == captureGeneration else { return }
        previewSizes = sizes
        let changed = ids.filter { id in
            guard let now = sizes[id] else { return false }
            guard let was = before[id] else { return true }
            return abs(now.width - was.width) > 2 || abs(now.height - was.height) > 2
        }
        guard !changed.isEmpty else { return }
        await nativeSystem.windowPreviews(windowIds: changed, maxSize: size) { [weak self] id, image in
            guard let self, generation == self.captureGeneration else { return }
            self.previews[id] = image
        }
    }
}
