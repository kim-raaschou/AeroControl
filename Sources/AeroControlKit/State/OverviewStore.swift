import AppKit
import Common
import Observation

@MainActor @Observable
public class OverviewStore {
    public private(set) var model = OverviewModel() {
        didSet {
            if let marking {
                self.marking = marking.kept(before: oldValue.windows(of: marking).map(\.window.windowId), after: model.windows(of: marking).map(\.window.windowId))
            }
            filterMatches = model.matching(filter)
        }
    }

    private let sync: AerospaceSync
    public let pictures: PictureStore
    public private(set) var error: String?
    public var filter: String = "" {
        didSet { filterMatches = model.matching(filter); marking = nil }
    }
    public private(set) var marking: Strip?
    public var strip: Strip? { marking.flatMap { m in m.app.map { _ in m } } }
    public var screen: (available: CGSize, frames: [Int: CGRect]) = (.zero, [:])
    public var scene: OverviewScene {
        OverviewScene(model: model, marking: marking, query: filter, matches: filterMatches, missingApp: missingApp, help: showingHelp,
                      error: error, available: screen.available, screens: screen.frames, sizes: pictures.sizes)
    }
    var drawn: [GridWalk.Card] { scene.grid }

    public var missingApp: AppRef?
    public var showingHelp = false

    public func endVisit() {
        following = false
        sync.stop()
        filter = ""
        marking = nil
        missingApp = nil
        showingHelp = false
        pictures.clear()
    }
    public var onShotDone: ((_ restoreFocus: Bool) -> Void)?

    public private(set) var recentWindows: [Int] = []

    public func noteFocus(_ windowId: Int) {
        recentWindows = [windowId] + recentWindows.filter { $0 != windowId }.prefix(63)
    }

    public var stripWindows: [ParsedWindow] { strip.map(model.windows(of:)) ?? [] }

    public var stripWorkspaces: [WorkspaceInfo] { strip.map { s in model.workspaces.filter { $0.windows.contains(where: s.owns) } } ?? [] }

    private func move(_ move: StripMove) {
        let drawn = drawn, order = drawn.flatMap { GridWalk.rows(of: $0).joined() }, cardOf = { (id: Int) in drawn.firstIndex { $0.windows[id] != nil } }
        marking = (marking ?? Strip(app: nil, marked: ringWindowId, centre: nil)).moved(move, ids: order, card: cardOf, cards: drawn)
    }

    private var pointer: CGPoint?

    public func notePointer(_ location: CGPoint) { pointer = location }

    public func point(_ windowId: Int, at location: CGPoint) {
        guard location != pointer, model.windows(of: marking).contains(where: { $0.window.windowId == windowId }) else { return }
        pointer = location
        marking = (marking ?? Strip(app: nil, marked: nil, centre: nil)).marking(windowId)
    }

    public private(set) var filterMatches: [ParsedWindow] = []

    public var ringWindowId: Int? { marking?.marked ?? filterMatches.first?.window.windowId ?? model.focusedWindowId }

    public var markedWorkspace: String? { marking?.marked.flatMap { id in model.workspaces.first { $0.standIn == id }?.name } }

    public var commandTarget: WindowInfo? { missingApp == nil ? ringWindowId.flatMap(model.window) : nil }

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.sync = AerospaceSync(runner: runner)
        self.pictures = PictureStore(bridge: nativeSystem)
    }

    public func reload() async { if let result = landed(await sync.read()) { send(.loaded(result)) } }

    private func landed(_ read: Result<OverviewResult, Error>) -> OverviewResult? {
        switch read {
        case .success(let result): error = nil; return result
        case .failure(let failure): error = "Load error: \(failure.localizedDescription)"; return nil
        }
    }

    public var following = false

    public func measurePreviews() async { await pictures.measure(model.workspaces.flatMap(\.windows).map(\.windowId)) }

    public func capturePreviews(maxSize: CGSize) async {
        await pictures.take((strip != nil ? stripWorkspaces : model.workspaces).flatMap { $0.windows.map(\.windowId) },
                            cards: model.workspaces.map { $0.windows.map(\.windowId) }, at: maxSize)
    }

    public func summonApp(_ app: AppRef) -> AppSummon {
        missingApp = nil
        let decision = AppSummon.decide(app: app, model: model, recent: recentWindows)
        guard case .pick(let opened) = decision else { return decision }
        marking = opened
        if following { requestRefresh() }
        return decision
    }

    public func handle(_ key: FilterKey) -> FilterKeyAction {
        if key == .help || (key == .escape && showingHelp) { showingHelp.toggle(); return .handled }
        if case .move(let move) = key { self.move(move); return .handled }
        if case .moveToWorkspace(let name) = key, let target = commandTarget { send(.action(.moveWindow(windowId: target.windowId, toWorkspace: name))); return .handled }
        if strip != nil || missingApp != nil { return handleStrip(key) }
        if key == .enter, let workspace = markedWorkspace { send(.action(.focusWorkspace(workspace))); return .handled }
        let action = filterKeyAction(query: filter, ring: ringWindowId, key: key)
        if case .setQuery(let query) = action { filter = query }
        return action
    }

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

    public func startListening() {
        sync.listen({ event in
            if case .focusChanged(let id?, _) = event { self.noteFocus(id) }
            if self.following { self.send(.event(event)) }
        }, resumed: { if self.following { await self.reload() } })
    }

    public func send(_ input: OverviewInput) {
        let (newState, effects) = Common.updateOverview(model, input)
        let focusMoved = newState.focusedWindowId != model.focusedWindowId
        let hadStrip = strip != nil
        if newState != model { model = newState }
        if focusMoved, let strip { marking = strip.following(model.focusedWindow) }
        if hadStrip, strip == nil { onShotDone?(true) }
        if case .action(let action) = input, action.isFocus { onShotDone?(action == .focusWindow(model.focusedWindowId)) }
        for effect in effects {
            switch effect {
            case .refresh: requestRefresh()
            case .run(let actions, let thenRead): run(actions, thenRead: thenRead)
            }
        }
    }

    private func run(_ actions: [AeroControlAction], thenRead: Bool) {
        Task { await sync.run(actions); if thenRead { requestRefresh() } }
    }

    private func requestRefresh() {
        sync.refresh { read, current in
            guard let result = self.landed(read) else { return }
            self.send(.loaded(result))
            let pictureGeneration = self.pictures.generation
            let (sizes, fresh) = await self.settled(result)
            guard current(), let sizes, pictureGeneration == self.pictures.generation else { return }
            self.pictures.sizes = sizes
            self.pictures.replace(fresh)
        }
    }

    private func settled(_ result: OverviewResult) async -> ([Int: CGSize]?, [Int: NSImage]) {
        let shown = result.workspaces.filter { ws in strip.map { ws.windows.contains(where: $0.owns) } ?? true }
        return await pictures.settled(result.workspaces.flatMap(\.windows).map(\.windowId), shown: shown)
    }

}
