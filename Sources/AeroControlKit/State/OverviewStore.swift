import AppKit
import SwiftUI
import Common

@MainActor @Observable
public class OverviewStore {
    public private(set) var model = OverviewModel() {
        didSet {
            if let strip {
                let before = oldValue.windowsInGridOrder.filter { $0.window.bundleId == strip.bundleId }.map(\.window.windowId)
                self.strip = strip.kept(before: before, after: stripWindows.map(\.window.windowId))
            }
            filterMatches = model.matching(filter)
        }
    }


    /// An app's icon, for the badge in a picture's corner: the one thing a picture does not say
    /// about a window is which app it is. The bridge keeps them, once per app, for good.
    public func icon(for bundleId: String) -> NSImage { nativeSystem.appIcon(bundleId: bundleId) }

    let runner: AerospaceProcessRunner
    let nativeSystem: NativeApiBridge
    /// Window previews, captured when the overview is summoned and dropped when it hides.
    /// They land a card at a time into a grid that is already on screen.
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
    /// is AeroSpace state in, AeroSpace work out.
    public var filter: String = "" {
        didSet { filterMatches = model.matching(filter) }
    }

    public private(set) var strip: Strip?
    /// An app `open` could not start, told on the strip's lane until the visit ends: a typo in a
    /// key's link is otherwise a key that does nothing.
    public var missingApp: AppRef?

    /// The visit is over: nothing to stay in sync with while hidden, no pictures kept, no query,
    /// and the next summon decides afresh whether there is a strip.
    public func endVisit() {
        following = false
        refreshTask?.cancel()
        refreshTask = nil
        filter = ""
        strip = nil
        missingApp = nil
        clearPreviews()
    }
    /// The one shot is over and the host closes the overview: after a focus action (the window
    /// or workspace asked for takes the keyboard), or when AeroSpace took the focus out of the
    /// overview for good (`restoreFocus`: the app that has it is brought forward).
    public var onShotDone: ((_ restoreFocus: Bool) -> Void)?

    /// Windows in the order they last had the focus, most recent first, as AeroSpace reports
    /// focus changes for as long as AeroControl runs (`startListening`): AeroSpace keeps no
    /// such order to ask for, and the window server's stacking does not follow it.
    public private(set) var recentWindows: [Int] = []

    public func noteFocus(_ windowId: Int) {
        recentWindows.removeAll { $0 == windowId }
        recentWindows.insert(windowId, at: 0)
        if recentWindows.count > 64 { recentWindows.removeLast() }
    }


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
        let workspaces = stripWorkspaces
        strip = strip?.stepped(direction, ids: stripWindows.map(\.window.windowId),
                               card: { id in workspaces.firstIndex { $0.windows.contains { $0.windowId == id } } })
    }

    /// Pointing marks, as in krn.overview's strip; a window that is not the app's is ignored.
    public func markStrip(_ windowId: Int) {
        guard stripWindows.contains(where: { $0.window.windowId == windowId }) else { return }
        strip = strip?.marking(windowId)
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

    /// Every window the query picks out, in the order the grid draws them. The grid, the ring
    /// and Enter all read this one list, so what the ring is on is what Enter focuses. Derived
    /// when the query or the model changes, not on read: every tile asks for the ring, and a
    /// computed property here was a scan of every title per tile per pass.
    public private(set) var filterMatches: [ParsedWindow] = []

    /// The window wearing the ring: the first match while the filter has any, AeroSpace's
    /// focused window otherwise — so on the map, and on a miss, the ring means what it always
    /// did. Nothing walks it: the overview follows AeroSpace, it does not steer it.
    public var ringWindowId: Int? {
        strip?.marked ?? filterMatches.first?.window.windowId ?? model.focusedWindowId
    }

    private var subscribeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    /// Pictures taken but not yet in `previews`. A workspace's land together once all of them
    /// are in, the cards in reading order and `cardEvery` apart: one by one, or each card as it
    /// was in, they came in all over the screen. And every picture stored redraws the whole
    /// overview — on the main thread that drew the map once per window and kept the captures
    /// still in flight from landing.
    private var arrivingPictures: [Int: NSImage] = [:]
    static let cardEvery: Duration = .milliseconds(25)
    /// Cards whose pictures are in, waiting their turn.
    private var cards: [[Int]] = []
    private var landing: Task<Void, Never>?

    private func land(_ card: [Int]) {
        cards.append(card)
        guard landing == nil else { return }
        let generation = captureGeneration
        landing = Task { [weak self] in
            while let self, generation == self.captureGeneration {
                guard !self.cards.isEmpty else { self.landing = nil; return }
                let card = Set(self.cards.removeFirst())
                let landed = self.arrivingPictures.filter { card.contains($0.key) }
                guard !landed.isEmpty else { continue }
                self.previews.merge(landed) { $1 }
                for id in landed.keys { self.arrivingPictures[id] = nil }
                try? await Task.sleep(for: Self.cardEvery)
            }
        }
    }

    /// Bumped by every capture and clear so a stale capture cannot overwrite newer state.
    private var captureGeneration = 0

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.runner = runner
        self.nativeSystem = nativeSystem
    }

    /// Reads AeroSpace's whole state and applies it. The overview is a one shot: the host
    /// awaits this at summon, so what is drawn is what AeroSpace says right now.
    public func reload() async {
        do {
            let result = try await loadOverview(using: runner)
            send(.loaded(result))
            error = nil
        } catch {
            self.error = "Load error: \(error.localizedDescription)"
        }
    }

    /// While the overview is up, AeroSpace's changes are read and drawn; while it is hidden only
    /// the focus changes are kept, for the order windows were used in.
    /// While the overview is up, every event is applied and read against AeroSpace; hidden, the
    /// listener only keeps the order of focus. `endVisit` turns it off.
    public var following = false

    // MARK: Window previews

    /// True when macOS lets us capture windows; decides the tile layout up front so the
    /// overview does not jump when the images arrive. Asked a few times a summon, by the host.
    public var previewsAvailable: Bool { nativeSystem.canCapturePreviews }

    /// Warms the capture path before `reload()`, so the system's window enumeration and
    /// AeroSpace's answer arrive together rather than one after the other.
    public func prepareCapture() { nativeSystem.prepareCapture() }

    public func requestPreviewAccess() { nativeSystem.requestPreviewAccess() }

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

    /// Captures a preview of every window drawn — the model's, or in the strip every window of
    /// its workspaces — once, at `maxSize`, each landing a moment after it is taken. Returns
    /// when all are in. A `clearPreviews()` in the meantime discards the rest.
    public func capturePreviews(maxSize: CGSize) async {
        captureSize = maxSize
        await take(strip == nil ? windowIds : stripWorkspaces.flatMap { $0.windows.map(\.windowId) }, at: maxSize)
    }

    /// Takes these windows' pictures, landing a workspace's once all of them and the cards before
    /// it are in; when the capture is, the rest — a workspace with a window that gave no picture.
    private func take(_ ids: [Int], at size: CGSize) async {
        let generation = captureGeneration
        let wanted = Set(ids)
        var waiting = model.workspaces.map { $0.windows.map(\.windowId).filter(wanted.contains) }.filter { !$0.isEmpty }
        await nativeSystem.windowPreviews(windowIds: ids, maxSize: size) { [weak self] id, image in
            guard let self, generation == self.captureGeneration else { return }
            self.arrivingPictures[id] = image
            while let card = waiting.first, card.allSatisfy({ self.arrivingPictures[$0] != nil }) {
                self.land(waiting.removeFirst())
            }
        }
        for card in waiting where generation == captureGeneration { land(card) }
        await landing?.value
    }

    /// The pixels a tile draws a picture at, as the tiles report them; a picture taken smaller
    /// is taken again at that size, the few that need it together once the reports settle
    /// (150 ms) — a filter narrowing to one window, a workspace alone on a card. What was asked
    /// is kept, so a window too small to give more is not asked again: no loop, no clock.
    public func wantPicture(_ id: Int, pixels: CGSize) {
        func covers(_ size: CGSize?) -> Bool { size.map { $0.width >= pixels.width * 0.95 && $0.height >= pixels.height * 0.95 } ?? false }
        guard previews[id] != nil, !covers(previews[id]?.size), !covers(asked[id]) else { return }
        wanted[id] = pixels
        guard sharpenTask == nil else { return }
        let generation = captureGeneration
        sharpenTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, generation == self.captureGeneration else { return }
            let wanted = self.wanted
            self.wanted = [:]
            self.sharpenTask = nil
            self.asked.merge(wanted) { $1 }
            let size = CGSize(width: wanted.values.map(\.width).max() ?? 0, height: wanted.values.map(\.height).max() ?? 0)
            await self.take(Array(wanted.keys).sorted(), at: size)
        }
    }
    private var wanted: [Int: CGSize] = [:]
    private var asked: [Int: CGSize] = [:]
    private var sharpenTask: Task<Void, Never>?

    /// The overview closes: its pictures go, with whatever was still being taken.
    private func clearPreviews() {
        captureGeneration += 1
        for task in [sharpenTask, landing] { task?.cancel() }
        sharpenTask = nil
        landing = nil
        cards = []
        wanted = [:]
        asked = [:]
        arrivingPictures = [:]
        captureSize = nil
        previews = [:]
        previewSizes = [:]
        PictureResampler.forget()
    }

    /// The key line for the app AeroSpace has focused, read from AeroSpace when asked: the menu
    /// copies it. Nil with nothing focused.
    public func focusedAppBinding() async -> String? {
        guard let json = try? await runner.run(AerospaceCommand.listFocusedWindow),
              let window = try? parseWindows(json: json).first?.window else { return nil }
        return aerospaceBinding(for: window)
    }

    /// One key on an app, `aerocontrol://app-id=<bundle id>` or `app-name=<name>`. The count is free; the model
    /// was just read, so the key does the right thing whatever the app's state:
    ///
    /// - none: start it; one: focus it;
    /// - two, and you are in one of them: the other — a toggle needs no picker;
    /// - more, or coming from elsewhere: the strip, the marking on the window after the
    ///   focused one, so Enter alone is Cmd-` with pictures.
    ///
    /// The first two lines are the link's own and hold with the strip off. The rest are the
    /// strip's: with it off the key is a passthrough — it brings the app forward, and macOS
    /// decides which window is in front, which for the app you are in changes nothing.
    public func summonApp(_ app: AppRef, picker: Bool) -> AppSummon {
        missingApp = nil
        let decision = AppSummon.decide(app: app, model: model, recent: recentWindows, picker: picker)
        guard case .pick(let opened) = decision else { return decision }
        strip = opened
        // Up already, the strip takes over another's: its pictures come as a focus event's would.
        if following { requestRefresh() }
        return decision
    }


    /// Type-to-filter. A keystroke the filter has a use for is applied here — the query and
    /// the ring are the store's — and the caller learns what became of it: `.none` is not
    /// ours, `.focus` is a pick the caller carries out, since focusing means hiding and the
    /// window is the caller's.
    public func handle(_ key: FilterKey) -> FilterKeyAction {
        if strip != nil || missingApp != nil { return handleStrip(key) }   // a notice is a strip of no windows
        let action = filterKeyAction(query: filter, ring: ringWindowId, key: key)
        if case .setQuery(let query) = action { filter = query }
        return action
    }

    /// A key in the strip, by its own rules (`AppStripModel.action`): steps move the marking,
    /// a key or Enter picks, Escape is the window's to close with; anything else is
    /// swallowed, since there is no typing in the strip.
    private func handleStrip(_ key: FilterKey) -> FilterKeyAction {
        let ids = stripWindows.map(\.window.windowId)
        switch AppStripModel.action(for: key, ids: ids, marked: strip?.marked) {
        case .step(let direction): stepStrip(direction)
        case .commit(let id): return .focus(windowId: id)
        case .cancel: return .none
        case .none: break
        }
        return .handled
    }

    /// One connection to AeroSpace's events for as long as AeroControl runs, from launch: one
    /// socket line per change, nothing taken from the screen.
    public func startListening() {
        guard subscribeTask == nil else { return }
        subscribeTask = Task.detached(priority: .utility) { [weak self] in
            var reconnecting = false
            while let self, !Task.isCancelled {
                // Everything that happened while the stream was down is lost — and we pass
                // `--no-send-initial`, so AeroSpace will not replay it either. Read once
                // after a reconnect so a dropped stream costs latency, never correctness.
                if reconnecting, await self.following { await self.reload() }
                do {
                    let stream = self.runner.subscribe(AerospaceCommand.subscribe)
                    for try await line in stream {
                        guard let event = AerospaceEvent.parse(line) else { continue }
                        if case .focusChanged(let id?, _) = event { await self.noteFocus(id) }
                        if await self.following { await self.send(.event(event)) }
                    }
                } catch {}
                guard !Task.isCancelled else { return }
                reconnecting = true
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    /// The one entrance: the reducer runs in the caller's turn, the model changes in one step
    /// (the grid animates its own reflow), and the effects run at once — each is a Task, and
    /// `.loaded` never asks for a refresh, so nothing here re-enters. A queue in
    /// front of this was tried and cut (2026-10-03): it added a turn of latency to every input
    /// and let an event land behind a later read, and bought no ordering the main actor did
    /// not already give.
    public func send(_ input: OverviewInput) {
        let (newState, effects) = Common.updateOverview(model, input)
        let focusMoved = newState.focusedWindowId != model.focusedWindowId
        let hadStrip = strip != nil
        if newState != model { model = newState }               // keeps the strip, or ends it with its app's last window
        // The strip follows AeroSpace's focus, from the event or the read: to another app of
        // several windows it turns, to one of a single window it is over.
        if focusMoved, let strip {
            self.strip = strip.following(model.focusedWindow, among: model.workspaces.flatMap(\.windows))
        }
        if hadStrip, strip == nil { onShotDone?(true) }        // over: the host closes and the focused app gets the keyboard
        if case .action(let action) = input, action.isFocus { onShotDone?(false) }
        for effect in effects {
            switch effect {
            case .refresh: requestRefresh()
            case .run(let actions, let thenRead): run(actions, thenRead: thenRead)
            }
        }
    }

    /// Runs the commands strictly one after another, then reads once if asked. A failing step
    /// does not stop the rest: AeroSpace stays the source of truth and the read shows what
    /// actually happened.
    private func run(_ actions: [AeroControlAction], thenRead: Bool) {
        Task { [weak self] in
            guard let self else { return }
            for action in actions {
                _ = try? await self.runner.run(AerospaceCommand.argv(for: action))
            }
            if thenRead { self.requestRefresh() }
        }
    }

    private var refreshGeneration = 0

    private func requestRefresh() {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: Self.readAfter)
            guard let self, !Task.isCancelled,
                  let result = try? await loadOverview(using: self.runner),
                  generation == self.refreshGeneration else { return }
            // The layout waits: nothing changes until the windows have settled and their pictures
            // are taken, then all of it at once. Drawn as it came, the card showed the new layout
            // with the old sizes and pictures, then every size the windows passed through, then the
            // pictures. Focus does not wait: it came with AeroSpace's event, before this read.
            let pictureGeneration = self.captureGeneration
            let (sizes, pictures) = await self.settled(result)
            guard !Task.isCancelled, generation == self.refreshGeneration else { return }
            self.error = nil
            self.send(.loaded(result))
            if let sizes, pictureGeneration == self.captureGeneration {
                self.previewSizes = sizes
                self.previews.merge(pictures) { $1 }
            }
        }
    }

    /// A refresh reads AeroSpace this long after the event: a key's `binding-triggered` comes before
    /// its commands run, and nothing after them, so a read at once was of the state before them.
    static let readAfter: Duration = .milliseconds(20)
    /// Then the windows' sizes are read from the window server every `settleEvery`, until two reads
    /// agree or `settleWithin` has passed: apps resize after AeroSpace moves their windows, in their
    /// own time, 70–280 ms measured. Taken at fixed times, a picture caught a window halfway.
    static let settleEvery: Duration = .milliseconds(50)
    static let settleWithin: Duration = .seconds(1)

    /// The windows' sizes once they stand still, and new pictures of those drawn whose picture no
    /// longer fits their shape, or that have none: the neighbours that widened into a hole, a window
    /// that appeared, the cards of the app the strip turns to. Nothing is stored, so a refresh cut
    /// off by the next loses nothing. Nil while the overview is hidden: `clearPreviews` has dropped
    /// the capture size.
    private func settled(_ result: OverviewResult) async -> ([Int: CGSize]?, [Int: NSImage]) {
        guard let size = captureSize else { return (nil, [:]) }
        let ids = result.workspaces.flatMap(\.windows).map(\.windowId)
        let deadline = ContinuousClock.now + Self.settleWithin
        var sizes = await nativeSystem.previewSizes(windowIds: ids)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: Self.settleEvery)
            let again = await nativeSystem.previewSizes(windowIds: ids)
            if again == sizes { break }
            sizes = again
        }
        let focusedApp = result.workspaces.flatMap(\.windows).first { $0.windowId == result.focus?.windowId }?.bundleId
        let apps = strip.map { [$0.bundleId, focusedApp] }
        let drawn = result.workspaces.filter { ws in apps.map { apps in ws.windows.contains { apps.contains($0.bundleId) } } ?? true }
        let stale = drawn.flatMap(\.windows).map(\.windowId).filter { id in sizes[id].map { !Self.sameShape(previews[id]?.size, $0) } ?? false }
        var pictures: [Int: NSImage] = [:]
        if !stale.isEmpty { await nativeSystem.windowPreviews(windowIds: stale, maxSize: size) { pictures[$0] = $1 } }
        return (sizes, pictures)
    }

    /// A picture fits its window while their shapes agree to 2 %; none fits nothing.
    private static func sameShape(_ picture: CGSize?, _ window: CGSize) -> Bool {
        guard let picture, picture.height > 0, window.height > 0 else { return false }
        return abs(picture.width / picture.height * window.height / window.width - 1) < 0.02
    }


}
