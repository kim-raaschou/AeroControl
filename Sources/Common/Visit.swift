public struct Visit: Equatable {
    public enum Effect: Sendable {
        case run([AeroControlAction], thenRead: Bool)
        case refresh
        case host(Host)
    }

    public enum Input: Sendable {
        case loaded(OverviewModel)
        case event(AerospaceEvent)
        case action(AeroControlAction)
        case merge(String, into: String)
    }

    public enum Host: Equatable, Sendable {
        case show(Summon)
        case hide
        case activate(bundleId: String)
        case launch(AppRef)
        case rebuild
    }

    public private(set) var model = OverviewModel()
    public private(set) var marking: Strip?
    public private(set) var query = ""
    public private(set) var missingApp: AppRef?
    public private(set) var recent: [Int] = []
    public private(set) var visible = false
    public private(set) var loading = false
    private var cameFrom: Int?

    public init() {}

    public var matches: [WindowInfo] { model.matching(query) }
    public var strip: Strip? { marking.flatMap { m in m.app.map { _ in m } } }
    public var stripWindows: [WindowInfo] { strip.map(model.windows(of:)) ?? [] }
    public var stripWorkspaces: [WorkspaceInfo] { strip.map { s in model.workspaces.filter { $0.windows.contains(where: s.owns) } } ?? [] }
    public var ringWindowId: Int? { marking?.marked ?? matches.first?.windowId ?? model.focusedWindow?.windowId }

    public mutating func apply(_ input: Input) -> [Effect] {
        var new = model, effects: [Effect] = []
        switch input {
        case .loaded(let read): new = read
        case .event(.focusChanged(let windowId, let workspace)): (new.focusedWindowId, new.focusedWorkspace, effects) = (windowId ?? 0, workspace, [.refresh])
        case .event(.changed): effects = [.refresh]
        case .merge(let source, let target): effects = merge(source, into: target)
        case .action(let action): effects = [.run([action], thenRead: !action.isFocus)]
        }
        let focusMoved = new.focusedWindowId != model.focusedWindowId, hadStrip = strip != nil
        if new != model {
            if let marking { self.marking = marking.kept(before: model.windows(of: marking).map(\.windowId), after: new.windows(of: marking).map(\.windowId)) }
            model = new
        }
        if focusMoved, let strip { marking = strip.following(model.focusedWindow) }
        var out = hadStrip && strip == nil ? hide(restoreFocus: true) : []
        if case .action(.focusWindow(let id)) = input { remember(id) }
        if case .action(let action) = input, action.isFocus { out += hide(restoreFocus: action == .focusWindow(model.focusedWindowId)) }
        return out + effects
    }

    private func merge(_ source: String, into target: String) -> [Effect] {
        guard source != target, let from = model.workspaces.first(where: { $0.name == source }), !from.windows.isEmpty else { return [] }
        let moves = from.windows.map { AeroControlAction.moveWindowQuietly(windowId: $0.windowId, toWorkspace: target) } + [.focusWorkspace(target)]
        let intoEmpty = model.workspaces.first { $0.name == target }?.windows.isEmpty == true
        guard intoEmpty, !from.rootLayout.isEmpty, let tiled = from.windows.first(where: \.isTiled) else { return [.run(moves, thenRead: true)] }
        return [.run(moves + [.focusWindow(tiled.windowId), .setLayout(from.rootLayout)], thenRead: true)]
    }

    public mutating func key(_ key: FilterKey, drawn: [GridWalk.Card]) -> [Effect] {
        guard visible else { return [] }
        let aside = strip != nil || missingApp != nil
        switch key {
        case .move(let step): return move(step, drawn: drawn)
        case .enter where missingApp == nil: return enter()
        case .escape where aside || query.isEmpty: return cancel()
        case .character(let c) where strip != nil:
            return FilterKey.workspaceNamed(String(c)).flatMap(stripWorkspaces.map(\.name).firstIndex).map { move(.card($0), drawn: drawn) } ?? []
        case _ where aside: break
        case .escape: setQuery("")
        case .backspace where !query.isEmpty: setQuery(String(query.dropLast()))
        case .character(let c) where !query.isEmpty || !c.isWhitespace: setQuery(query + String(c))
        default: break
        }
        return []
    }

    private func focus(_ ring: Int) -> AeroControlAction {
        model.workspaces.first { $0.standIn == ring }.map { .focusWorkspace($0.name) } ?? .focusWindow(ring)
    }

    private mutating func enter() -> [Effect] {
        guard let ring = ringWindowId else { return hide(restoreFocus: true) }
        return apply(.action(focus(ring)))
    }

    private mutating func move(_ step: StripMove, drawn: [GridWalk.Card]) -> [Effect] {
        marking = (marking ?? Strip(app: nil, marked: ringWindowId, centre: nil)).moved(step, cards: drawn)
        return follow()
    }

    public func follow() -> [Effect] {
        guard let ring = ringWindowId, ring != model.focusedWindowId else { return [] }
        return [.run([focus(ring)], thenRead: false)]
    }

    public mutating func cancel() -> [Effect] {
        guard let back = cameFrom, back != model.focusedWindowId || back != ringWindowId, model.window(back) != nil else { return hide(restoreFocus: true) }
        return hide(restoreFocus: false) + [.run([.focusWindow(back)], thenRead: false)]
    }

    public mutating func summon(_ summon: Summon, drawn: [GridWalk.Card]) -> [Effect] {
        guard !loading else { return [] }
        switch summon {
        case _ where !visible: break
        case .map where strip == nil && missingApp == nil: return cancel()
        case .app(let ref) where strip != nil && stripWindows.contains(where: ref.matches): return move(.next, drawn: drawn)
        default: break
        }
        (visible, loading) = (true, true)
        return [.host(.show(summon))]
    }

    public mutating func summoned(_ summon: Summon) -> [Effect] {
        let fresh = cameFrom == nil
        (loading, cameFrom) = (false, cameFrom ?? model.focusedWindowId)
        guard visible, case .app(let ref) = summon else { return [] }
        return open(ref, fresh: fresh)
    }

    private mutating func open(_ ref: AppRef, fresh: Bool) -> [Effect] {
        missingApp = nil
        let windows = model.windowsInGridOrder.filter(ref.matches)
        let focusedAt = windows.firstIndex { $0.windowId == model.focusedWindowId }
        switch (windows.count, focusedAt) {
        case (0, _): return hide(restoreFocus: false) + [.host(.launch(ref))]
        case (1, _): return apply(.action(.focusWindow(windows[0].windowId)))
        case (2, let at?): return apply(.action(.focusWindow(windows[1 - at].windowId)))
        case (_, nil) where fresh: return apply(.action(.focusWindow(recent.first { id in windows.contains { $0.windowId == id } } ?? windows[0].windowId)))
        default:
            marking = .opened(windows[0].bundleId, origin: focusedAt.map { _ in model.focusedWindowId }, ids: windows.map(\.windowId), recent: recent)
            return follow()
        }
    }

    public mutating func hide(restoreFocus: Bool) -> [Effect] {
        guard visible else { return [] }
        visible = false
        return [.host(.hide)] + (restoreFocus ? model.focusedWindow.map { [.host(.activate(bundleId: $0.bundleId))] } ?? [] : [])
    }

    public mutating func launchFailed(_ ref: AppRef) -> [Effect] {
        guard !visible else { return [] }
        (visible, missingApp) = (true, ref)
        return [.host(.rebuild)]
    }

    public mutating func point(_ windowId: Int) {
        guard model.windows(of: marking).contains(where: { $0.windowId == windowId }) else { return }
        marking = (marking ?? Strip(app: nil, marked: nil, centre: nil)).marking(windowId)
    }

    public mutating func noteFocus(_ windowId: Int) { if !visible { remember(windowId) } }

    private mutating func remember(_ id: Int) { recent = [id] + recent.filter { $0 != id }.prefix(63) }

    public mutating func end() {
        setQuery("")
        missingApp = nil
        if !visible { cameFrom = nil }
    }

    private mutating func setQuery(_ text: String) {
        (query, marking) = (text, nil)
    }
}
