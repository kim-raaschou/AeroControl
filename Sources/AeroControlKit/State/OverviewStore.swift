import AppKit
import SwiftUI
import Common

@MainActor @Observable
public class OverviewStore {
    public private(set) var model = OverviewModel() {
        didSet {
            if let marking {    // the strip's windows, or the map's: all of them
                self.marking = marking.kept(before: oldValue.windows(of: marking).map(\.window.windowId), after: model.windows(of: marking).map(\.window.windowId))
            }
            filterMatches = model.matching(filter)
        }
    }


    let runner: AerospaceProcessRunner
    /// The windows' pictures this visit, kept and taken by their own store; this one says which windows.
    public let pictures: PictureStore
    public private(set) var error: String?
    /// What the user has typed into the overview. UI state that drives no AeroSpace work, so
    /// it lives here rather than in the model: the reducer's contract
    /// is AeroSpace state in, AeroSpace work out.
    public var filter: String = "" {
        didSet { filterMatches = model.matching(filter); marking = nil }
    }
    /// The marking: the strip's, or the map's once a key or the pointer has moved the ring — until
    /// then the ring is AeroSpace's focus, or the first match. AeroSpace moving its focus moves
    /// the outline, not this. One value and one set of rules for both (`Strip`).
    public private(set) var marking: Strip?
    /// The strip that is up, if the marking is one's.
    public var strip: Strip? { marking.flatMap { m in m.app.map { _ in m } } }
    /// The cards as the map or the strip last laid them out, every window where it is drawn: the
    /// keys and the pointer go by these. An empty workspace's card holds its stand-in.
    @ObservationIgnored public var drawn: [GridWalk.Card] = []

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
        marking = nil
        drawn = []
        missingApp = nil
        pictures.clear()
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
    public var stripWindows: [ParsedWindow] { strip.map(model.windows(of:)) ?? [] }

    /// The workspaces that hold the strip's app, whole: a card mirrors all of a workspace, the
    /// other apps' windows drawn grey behind the app's, not only the app's windows.
    public var stripWorkspaces: [WorkspaceInfo] { strip.map { s in model.workspaces.filter { $0.windows.contains(where: s.owns) } } ?? [] }

    /// A key moves the marking, the map's or the strip's, through the cards as drawn
    /// (`Strip.moved`): ← and → through a card's windows in reading order and on to the next, an
    /// empty workspace standing in as one window the size of its card; the map's marking starts
    /// from the ring. While there is a query, the matches are all that is drawn.
    private func move(_ move: StripMove) {
        let order = drawn.flatMap { GridWalk.rows(of: $0).joined() }, cardOf = { [drawn] (id: Int) in drawn.firstIndex { $0.windows[id] != nil } }
        marking = (marking ?? Strip(app: nil, marked: ringWindowId, centre: nil)).moved(move, ids: order, card: cardOf, cards: drawn)
    }

    /// Where the mouse was when the overview last heard from it, in screen points.
    private var pointer: CGPoint?

    /// The mouse's place as the map or the strip opens, so a card that slides or appears under
    /// it is not pointed at.
    public func notePointer(_ location: CGPoint) { pointer = location }

    /// The pointer entered a window: it marks it, the map's ring or the strip's marking alike — in
    /// the strip only the app's own, as in krn.overview's — and only if the mouse moved. A hover
    /// also fires when the row slides, or the overview opens, under a hand that is still, and
    /// that must not take the marking away from the keys.
    public func point(_ windowId: Int, at location: CGPoint) {
        guard location != pointer, model.windows(of: marking).contains(where: { $0.window.windowId == windowId }) else { return }
        pointer = location
        marking = (marking ?? Strip(app: nil, marked: nil, centre: nil)).marking(windowId)
    }

    /// Every window the query picks out, in the order the grid draws them. The grid, the ring
    /// and Enter all read this one list, so what the ring is on is what Enter focuses. Derived
    /// when the query or the model changes, not on read: every tile asks for the ring, and a
    /// computed property here was a scan of every title per tile per pass.
    public private(set) var filterMatches: [ParsedWindow] = []

    /// The window wearing the ring: the marking, else the first match while the filter has any,
    /// else AeroSpace's focused window. Until a key or the pointer moves it the map follows
    /// AeroSpace; the thin outline always does.
    public var ringWindowId: Int? { marking?.marked ?? filterMatches.first?.window.windowId ?? model.focusedWindowId }

    /// The empty workspace the map's ring is on, a stop of its own for the keys: its card wears
    /// the ring, and Enter switches to it. Its marking is its stand-in, `-1 - its index`
    /// (`AeroControlLayout.MapCard`), which no window has.
    public var markedWorkspace: String? { marking?.marked.flatMap { Dictionary(model.workspaces.enumerated().map { (-1 - $0.offset, $0.element.name) }) { a, _ in a }[$0] } }


    /// The window ⌘W closes and whose app ⌘Q quits, as its × and the app's own ⌘Q would: the one
    /// under the ring, the map's or the strip's, which says on screen what goes.
    public var commandTarget: WindowInfo? {
        (missingApp.map { _ in [] } ?? model.workspaces.flatMap(\.windows)).first { $0.windowId == ringWindowId }
    }

    private var subscribeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.runner = runner
        self.pictures = PictureStore(bridge: nativeSystem)
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

    // MARK: Window previews — the store says which windows; `pictures` keeps them

    private var windowIds: [Int] { model.workspaces.flatMap(\.windows).map(\.windowId) }

    /// Reads every window's size before any picture is taken (`PictureStore.measure`).
    public func measurePreviews() async { await pictures.measure(windowIds) }

    /// Captures a preview of every window drawn — the model's, or in the strip every window of
    /// its workspaces — once, at `maxSize`; returns when all are in (`PictureStore.take`).
    public func capturePreviews(maxSize: CGSize) async {
        await pictures.take(strip == nil ? windowIds : stripWorkspaces.flatMap { $0.windows.map(\.windowId) },
                            cards: model.workspaces.map { $0.windows.map(\.windowId) }, at: maxSize)
    }

    /// One key on an app, `aerocontrol://app-id=<bundle id>` or `app-name=<name>`. The count is free; the model
    /// was just read, so the key does the right thing whatever the app's state:
    ///
    /// - none: start it; one: focus it;
    /// - two, and you are in one of them: the other — a toggle needs no strip;
    /// - more, or coming from elsewhere: the strip, the marking on the app's window used last
    ///   before the focused one, so Enter alone is Cmd-` with pictures.
    public func summonApp(_ app: AppRef) -> AppSummon {
        missingApp = nil
        let decision = AppSummon.decide(app: app, model: model, recent: recentWindows)
        guard case .pick(let opened) = decision else { return decision }
        marking = opened
        // Up already, the strip takes over another's: its pictures come as a focus event's would.
        if following { requestRefresh() }
        return decision
    }


    /// Type-to-filter. A keystroke the filter has a use for is applied here — the query and
    /// the ring are the store's — and the caller learns what became of it: `.none` is not
    /// ours, `.focus` is a pick the caller carries out, since focusing means hiding and the
    /// window is the caller's.
    public func handle(_ key: FilterKey) -> FilterKeyAction {
        if case .move(let move) = key { self.move(move); return .handled }
        // ⇧⌘ and a workspace's name: the window under the ring goes there, and the overview stays, as after ⌘W.
        if case .moveToWorkspace(let name) = key, let target = commandTarget { send(.action(.moveWindow(windowId: target.windowId, toWorkspace: name))); return .handled }
        if strip != nil || missingApp != nil { return handleStrip(key) }   // a notice is a strip of no windows
        if key == .enter, let workspace = markedWorkspace { send(.action(.focusWorkspace(workspace))); return .handled }
        let action = filterKeyAction(query: filter, ring: ringWindowId, key: key)
        if case .setQuery(let query) = action { filter = query }
        return action
    }

    /// A key in the strip, by its own rules (`AppStripModel.action`): steps move the marking,
    /// a key or Enter picks, Escape is the window's to close with; anything else is
    /// swallowed, since there is no typing in the strip.
    private func handleStrip(_ key: FilterKey) -> FilterKeyAction {
        let ids = stripWindows.map(\.window.windowId)
        switch AppStripModel.action(for: key, ids: ids, marked: strip?.marked, workspaces: stripWorkspaces.map(\.name)) {
        case .move(let move): self.move(move)
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
        // AeroSpace's focus decides, from the event or the read: out of the strip's app, it is over.
        if focusMoved, let strip { marking = strip.following(model.focusedWindow) }
        if hadStrip, strip == nil { onShotDone?(true) }        // over: the host closes and the focused app gets the keyboard
        // A focus ends the shot and AeroSpace hands the window the keyboard; on the window it has
        // focused already its `focus` does nothing, and the host gives the app the keyboard itself.
        if case .action(let action) = input, action.isFocus { onShotDone?(action == .focusWindow(model.focusedWindowId)) }
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
            if case .focusWindow(let id) = actions.last { await self.focusAgainIfMissed(id) }
            if thenRead { self.requestRefresh() }
        }
    }

    /// WORKAROUND for AeroSpace issue 101, https://github.com/nikitabobko/AeroSpace/issues/101 —
    /// remove once AeroSpace fixes it. Asked to focus a window of an app that has windows on more
    /// than one monitor, AeroSpace activates the app, and macOS, as the activation completes, gives
    /// the keyboard back to the app's last key window, often on the other monitor; AeroSpace
    /// follows. Asked again once the app is active, the focus holds. So a moment after a focus,
    /// if AeroSpace's focus is elsewhere, it is asked for once more.
    private func focusAgainIfMissed(_ windowId: Int) async {
        try? await Task.sleep(for: .milliseconds(300))
        if await loadFocusedWindow(using: runner)?.windowId != windowId { _ = try? await runner.run(AerospaceCommand.argv(for: .focusWindow(windowId))) }
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
            let pictureGeneration = self.pictures.generation
            let (sizes, fresh) = await self.settled(result)
            guard !Task.isCancelled, generation == self.refreshGeneration else { return }
            self.error = nil
            self.send(.loaded(result))
            if let sizes, pictureGeneration == self.pictures.generation {
                self.pictures.sizes = sizes
                self.pictures.replace(fresh)
            }
        }
    }

    /// A refresh reads AeroSpace this long after the event: a key's `binding-triggered` comes before
    /// its commands run, and nothing after them, so a read at once was of the state before them.
    static let readAfter: Duration = .milliseconds(20)
    /// What `PictureStore.settled` says for the windows drawn: in a strip only its app's workspaces.
    private func settled(_ result: OverviewResult) async -> ([Int: CGSize]?, [Int: NSImage]) {
        let shown = result.workspaces.filter { ws in strip.map { ws.windows.contains(where: $0.owns) } ?? true }
        return await pictures.settled(result.workspaces.flatMap(\.windows).map(\.windowId), shown: shown)
    }


}
