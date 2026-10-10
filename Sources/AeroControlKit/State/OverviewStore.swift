import AppKit
import SwiftUI
import Common

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

    let runner: AerospaceProcessRunner
    public let pictures: PictureStore
    public private(set) var error: String?
    public var filter: String = "" {
        didSet { filterMatches = model.matching(filter); marking = nil }
    }
    public private(set) var marking: Strip?
    public var strip: Strip? { marking.flatMap { m in m.app.map { _ in m } } }
    public var screen: (available: CGSize, frames: [Int: CGRect]) = (.zero, [:])
    public var usable: CGSize { AeroControlLayout.usable(screen.available) }

    public var filtering: Bool { strip == nil && !model.workspaces(holding: filterMatches).isEmpty }
    public var shown: [WorkspaceInfo] { strip != nil ? stripWorkspaces : filtering ? model.workspaces(holding: filterMatches) : model.workspaces }
    public var cards: [AeroControlLayout.MapCard] {
        AeroControlLayout.mapLayout(workspaces: shown, sizes: pictures.sizes, screens: screen.frames, available: screen.available, usable: usable, filtering: filtering)
    }
    public var stripLayout: AeroControlLayout.StripLayout { AeroControlLayout.stripLayout(groups: stripWorkspaces, bundleId: strip?.app ?? "", sizes: pictures.sizes,
        screens: screen.frames, fallbackScreen: CGRect(origin: .zero, size: screen.available), viewWidth: usable.width, panelHeight: usable.height) }
    var drawn: [GridWalk.Card] { strip != nil ? stripLayout.grid : cards.map(\.grid) }

    public var missingApp: AppRef?

    public func endVisit() {
        following = false
        refreshTask?.cancel()
        refreshTask = nil
        filter = ""
        marking = nil
        missingApp = nil
        pictures.clear()
    }
    public var onShotDone: ((_ restoreFocus: Bool) -> Void)?

    public private(set) var recentWindows: [Int] = []

    public func noteFocus(_ windowId: Int) {
        recentWindows.removeAll { $0 == windowId }
        recentWindows.insert(windowId, at: 0)
        if recentWindows.count > 64 { recentWindows.removeLast() }
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

    public var markedWorkspace: String? { marking?.marked.flatMap { Dictionary(model.workspaces.enumerated().map { (-1 - $0.offset, $0.element.name) }) { a, _ in a }[$0] } }

    public var commandTarget: WindowInfo? {
        (missingApp.map { _ in [] } ?? model.workspaces.flatMap(\.windows)).first { $0.windowId == ringWindowId }
    }

    private var subscribeTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.runner = runner
        self.pictures = PictureStore(bridge: nativeSystem)
    }

    public func reload() async {
        do {
            let result = try await loadOverview(using: runner)
            send(.loaded(result))
            error = nil
        } catch {
            self.error = "Load error: \(error.localizedDescription)"
        }
    }

    public var following = false

    private var windowIds: [Int] { model.workspaces.flatMap(\.windows).map(\.windowId) }

    public func measurePreviews() async { await pictures.measure(windowIds) }

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
        guard subscribeTask == nil else { return }
        subscribeTask = Task.detached(priority: .utility) { [weak self] in
            var reconnecting = false
            while let self, !Task.isCancelled {
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
            self.error = nil
            self.send(.loaded(result))
            let pictureGeneration = self.pictures.generation
            let (sizes, fresh) = await self.settled(result)
            guard !Task.isCancelled, generation == self.refreshGeneration else { return }
            if let sizes, pictureGeneration == self.pictures.generation {
                self.pictures.sizes = sizes
                self.pictures.replace(fresh)
            }
        }
    }

    static let readAfter: Duration = .milliseconds(20)
    private func settled(_ result: OverviewResult) async -> ([Int: CGSize]?, [Int: NSImage]) {
        let shown = result.workspaces.filter { ws in strip.map { ws.windows.contains(where: $0.owns) } ?? true }
        return await pictures.settled(result.workspaces.flatMap(\.windows).map(\.windowId), shown: shown)
    }

}
