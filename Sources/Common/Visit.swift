public struct Visit: Equatable {
    public enum Effect: Sendable {
        case run([AeroControlAction], thenRead: Bool)
        case refresh
        case capture
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
        case quit(bundleId: String)
        case launch(AppRef)
        case rebuild
    }

    public private(set) var model = OverviewModel()
    public private(set) var marking: Strip?
    public private(set) var query = ""
    public private(set) var matches: [WindowInfo] = []
    public private(set) var missingApp: AppRef?
    public private(set) var recent: [Int] = []
    public private(set) var visible = false
    private var loading = false

    public init() {}

    public var strip: Strip? { marking.flatMap { m in m.app.map { _ in m } } }
    public var stripWindows: [WindowInfo] { strip.map(model.windows(of:)) ?? [] }
    public var stripWorkspaces: [WorkspaceInfo] { strip.map { s in model.workspaces.filter { $0.windows.contains(where: s.owns) } } ?? [] }
    public var shownWorkspaces: [WorkspaceInfo] { strip == nil ? model.workspaces : stripWorkspaces }
    public var ringWindowId: Int? { marking?.marked ?? matches.first?.windowId ?? model.focusedWindow?.windowId }
    public var commandTarget: WindowInfo? { missingApp == nil ? ringWindowId.flatMap(model.window) : nil }

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
            matches = model.matching(query)
        }
        if focusMoved, let strip { marking = strip.following(model.focusedWindow) }
        var out = hadStrip && strip == nil ? hide(restoreFocus: true) : []
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

    public mutating func key(_ key: FilterKey, drawn: [GridWalk.Card]) -> (Bool, [Effect]) {
        switch key {
        case _ where !visible: return (false, [])
        case .move(let step): return (true, move(step, drawn: drawn))
        case .moveToWorkspace(let name) where commandTarget != nil: return (true, apply(.action(.moveWindow(windowId: commandTarget!.windowId, toWorkspace: name))))
        case .close: return (true, commandTarget.map { apply(.action(.closeWindow($0.windowId))) } ?? [])
        case .quit: return (true, commandTarget.map { [.host(.quit(bundleId: $0.bundleId))] } ?? [])
        case .enter where missingApp == nil: return (true, enter())
        case _ where strip != nil || missingApp != nil: return stripKey(key, drawn: drawn)
        case .escape where !query.isEmpty: setQuery("")
        case .escape: return (true, hide(restoreFocus: true))
        case .backspace where !query.isEmpty: setQuery(String(query.dropLast()))
        case .character(let c) where !query.isEmpty || !c.isWhitespace: setQuery(query + String(c))
        default: return (false, [])
        }
        return (true, [])
    }

    private mutating func enter() -> [Effect] {
        let workspace = marking?.marked.flatMap { id in model.workspaces.first { $0.standIn == id }?.name }
        guard let ring = workspace.map(AeroControlAction.focusWorkspace) ?? ringWindowId.map(AeroControlAction.focusWindow) else { return hide(restoreFocus: true) }
        return apply(.action(ring))
    }

    private mutating func stripKey(_ key: FilterKey, drawn: [GridWalk.Card]) -> (Bool, [Effect]) {
        let names = stripWorkspaces.map(\.name), card = { (c: Character) in FilterKey.workspaceNamed(String(c)).flatMap(names.firstIndex) }
        switch key {
        case .escape: return (true, hide(restoreFocus: true))
        case .character(let c) where card(c) != nil: _ = move(.card(card(c)!), drawn: drawn)
        default: break
        }
        return (true, [])
    }

    private mutating func move(_ step: StripMove, drawn: [GridWalk.Card]) -> [Effect] {
        marking = (marking ?? Strip(app: nil, marked: ringWindowId, centre: nil)).moved(step, cards: drawn)
        let ringed = model.workspaces.first { ws in ws.standIn == ringWindowId || ws.windows.contains { $0.windowId == ringWindowId } }?.name
        guard strip == nil, let ringed, ringed != model.focusedWorkspace else { return [] }
        return [.run([.focusWorkspace(ringed)], thenRead: false)]
    }

    public mutating func summon(_ summon: Summon, drawn: [GridWalk.Card]) -> [Effect] {
        guard visible else { (visible, loading) = (true, true); return [.host(.show(summon))] }
        guard !loading else { return [] }
        guard case .app(let ref) = summon else { return hide(restoreFocus: true) }
        if strip != nil, stripWindows.contains(where: ref.matches) { return move(.window(1), drawn: drawn) }
        return open(ref, takingOver: true)
    }

    public mutating func summoned(_ summon: Summon) -> [Effect] {
        loading = false
        guard visible, case .app(let ref) = summon else { return [] }
        return open(ref, takingOver: false)
    }

    private mutating func open(_ ref: AppRef, takingOver: Bool) -> [Effect] {
        missingApp = nil
        let windows = model.windowsInGridOrder.filter(ref.matches)
        let focusedAt = windows.firstIndex { $0.windowId == model.focusedWindowId }
        switch (windows.count, focusedAt) {
        case (0, _): return hide(restoreFocus: false) + [.host(.launch(ref))]
        case (1, _): return apply(.action(.focusWindow(windows[0].windowId)))
        case (2, let at?): return apply(.action(.focusWindow(windows[1 - at].windowId)))
        default:
            marking = .opened(windows[0].bundleId, origin: focusedAt.map { _ in model.focusedWindowId }, ids: windows.map(\.windowId), recent: recent)
            return takingOver ? [.capture] : []
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

    public mutating func noteFocus(_ windowId: Int) { recent = [windowId] + recent.filter { $0 != windowId }.prefix(63) }

    public mutating func end() {
        setQuery("")
        missingApp = nil
    }

    private mutating func setQuery(_ text: String) {
        (query, matches, marking) = (text, model.matching(text), nil)
    }
}
