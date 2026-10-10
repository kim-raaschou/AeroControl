import CoreGraphics
import Foundation

public struct OverviewScene: Sendable {
    public enum Body: Equatable, Sendable { case error(String), nothing, map, strip }

    public enum Lane: Equatable, Sendable {
        case keys
        case query(String, miss: Bool)
        case app(name: String, bundleId: String, summary: String)
        case notice(name: String, reason: String)
    }

    public struct Tile: Equatable, Sendable {
        public let window: WindowInfo
        public let frame: CGRect
        public let ringed: Bool
        public let origin: Bool
        public let ghost: Bool
        public let faded: Bool
        public let captioned: Bool
        public let key: String?
        public let keyMarked: Bool
        public let stacking: Double
    }

    public struct Card: Equatable, Sendable {
        public let workspace: WorkspaceInfo
        public let frame: CGRect
        public let focused: Bool
        public let monitor: String?
        public let ringed: Bool
        public let cut: Bool
        public let tiles: [Tile]
    }

    public let body: Body
    public let size: CGSize
    public let cards: [Card]
    public let lane: Lane
    public let help: Bool
    public let ringed: Int?
    public let held: Int?
    public let grid: [GridWalk.Card]

    public init(_ visit: Visit, error: String?, available: CGSize, screens: [Int: CGRect], sizes: [Int: CGSize]) {
        let model = visit.model, strip = visit.strip, mine = visit.stripWindows, ring = visit.ringWindowId
        let usable = AeroControlLayout.usable(available)
        (size, help, ringed, lane) = (usable, visit.help, ring, Self.lane(visit))
        func tile(_ w: WindowInfo, _ frame: CGRect, ghost: Bool = false, faded: Bool = false, captioned: Bool = false, key: String? = nil) -> Tile {
            Tile(window: w, frame: frame, ringed: w.windowId == ring, origin: w.windowId != ring && w.windowId == model.focusedWindowId, ghost: ghost,
                 faded: faded, captioned: captioned, key: key, keyMarked: key != nil && w.windowId == strip?.marked,
                 stacking: AeroControlLayout.stacking(windowId: w.windowId, focused: model.focusedWindowId, ghosts: ghost ? [w.windowId] : []))
        }
        func card(_ ws: WorkspaceInfo, _ frame: CGRect, cut: Bool = false, tiles: [Tile]) -> Card {
            Card(workspace: ws, frame: frame, focused: ws.name == model.focusedWorkspace,
                 monitor: model.spansMonitors && !ws.monitorShortName.isEmpty ? ws.monitorShortName : nil, ringed: ring == ws.standIn, cut: cut, tiles: tiles)
        }
        if let error {
            (body, cards, grid, held) = (.error(error), [], [], nil)
        } else if model.workspaces.isEmpty || visit.missingApp != nil {
            (body, cards, grid, held) = (.nothing, [], [], nil)
        } else if let strip, !mine.isEmpty {
            let groups = model.workspaces.filter { $0.windows.contains(where: strip.owns) }
            let layout = AeroControlLayout.stripLayout(groups: groups, bundleId: strip.app ?? "", sizes: sizes, screens: screens,
                                                       fallbackScreen: CGRect(origin: .zero, size: available), viewWidth: usable.width, panelHeight: usable.height)
            let ids = mine.map(\.window.windowId)
            body = .strip
            held = layout.cards.firstIndex { c in strip.centre.map { c.frames[$0] != nil } ?? false }
            grid = layout.grid
            cards = AeroControlLayout.stripPlacements(layout, centre: strip.centre, viewWidth: usable.width).map { placed in
                let ws = groups[placed.card], laid = layout.cards[placed.card]
                return card(ws, CGRect(x: placed.x, y: 0, width: laid.span.width, height: layout.height),
                            cut: placed.x < 0 || placed.x + laid.span.width > usable.width,
                            tiles: ws.windows.compactMap { w in laid.frames[w.windowId].map { f in
                                tile(w, f, faded: laid.others.contains(w.windowId), key: ids.firstIndex(of: w.windowId).flatMap(AppStripModel.keyLabel)) } })
            }
        } else {
            let filtered = model.workspaces(holding: visit.matches), filtering = !filtered.isEmpty
            let shown = filtering ? filtered : model.workspaces
            let laid = AeroControlLayout.mapLayout(workspaces: shown, sizes: sizes, screens: screens, available: available, usable: usable, filtering: filtering)
            (body, held, grid) = (.map, nil, laid.map(\.grid))
            cards = zip(shown, laid).map { ws, c in
                card(ws, c.frame, tiles: ws.windows.map { w in
                    let f = c.frames[w.windowId] ?? .zero
                    return tile(w, f, ghost: c.ghosts.contains(w.windowId),
                                captioned: (filtering || sizes[w.windowId] == nil) && f.height >= AeroControlLayout.captionLane + AeroControlLayout.minPictureHeight)
                })
            }
        }
    }

    private static func lane(_ visit: Visit) -> Lane {
        if let missing = visit.missingApp?.notFound { return .notice(name: missing.name, reason: missing.reason) }
        if let strip = visit.strip, let first = visit.stripWindows.first?.window {
            return .app(name: first.appName, bundleId: strip.app ?? "", summary: AppStripModel.summary(visit.stripWindows, marked: strip.marked))
        }
        if let marked = visit.marking?.marked, let ringed = visit.model.windowsInGridOrder.first(where: { $0.window.windowId == marked }) {
            return .app(name: ringed.window.appName, bundleId: ringed.window.bundleId, summary: ringed.window.caption + " · ws " + ringed.workspace)
        }
        if visit.query.isEmpty { return .keys }
        return .query(visit.query, miss: visit.matches.isEmpty && visit.query.trimmingCharacters(in: .whitespaces).count >= OverviewModel.minQueryLength)
    }
}
