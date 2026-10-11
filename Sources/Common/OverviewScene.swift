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
    public let ringed: Int?
    public let held: Int?
    public let grid: [GridWalk.Card]

    public init(_ visit: Visit, error: String?, available: CGSize, screens: [Int: CGRect], frames: [Int: CGRect]) {
        let model = visit.model, strip = visit.strip, mine = visit.stripWindows, ring = visit.ringWindowId
        let usable = AeroControlLayout.usable(available)
        (size, ringed, lane) = (usable, ring, Self.lane(visit))
        func tile(_ w: WindowInfo, _ frame: CGRect, ghost: Bool = false, faded: Bool = false, captioned: Bool = false) -> Tile {
            Tile(window: w, frame: frame, ringed: w.windowId == ring, origin: w.windowId != ring && w.windowId == model.focusedWindowId, ghost: ghost,
                 faded: faded, captioned: captioned,
                 stacking: ghost ? 2 : w.windowId == model.focusedWindowId ? 1 : 0)
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
            let groups = visit.stripWorkspaces
            let laid = AeroControlLayout.stripLayout(groups: groups, bundleId: strip.app ?? "", frames: frames, screens: screens, available: available)
            let holding = laid.firstIndex { c in strip.centre.map { c.frames[$0] != nil } ?? false }
            let offset = AeroControlLayout.stripOffset(laid, held: holding ?? 0, viewWidth: usable.width)
            (body, held, grid) = (.strip, holding, laid.map(\.grid))
            cards = zip(groups, laid).map { ws, c in
                let frame = c.frame.offsetBy(dx: offset, dy: 0)
                return card(ws, frame, cut: frame.minX < 0 || frame.maxX > usable.width,
                            tiles: ws.windows.compactMap { w in c.frames[w.windowId].map { f in
                                tile(w, f, ghost: c.ghosts.contains(w.windowId), faded: c.others.contains(w.windowId)) } })
            }
        } else {
            let filtered = model.workspaces(holding: visit.matches), filtering = !filtered.isEmpty
            let shown = filtering ? filtered : model.workspaces
            let laid = AeroControlLayout.mapLayout(workspaces: shown, frames: frames, screens: screens, available: available, filtering: filtering)
            (body, held, grid) = (.map, nil, laid.map(\.grid))
            cards = zip(shown, laid).map { ws, c in
                card(ws, c.frame, tiles: ws.windows.map { w in
                    let f = c.frames[w.windowId] ?? .zero
                    return tile(w, f, ghost: c.ghosts.contains(w.windowId),
                                captioned: (filtering || frames[w.windowId] == nil) && f.height >= AeroControlLayout.captionLane + AeroControlLayout.minPictureHeight)
                })
            }
        }
    }

    private static func summary(_ windows: [WindowInfo], marked: Int?) -> String {
        let workspaces = Set(windows.map(\.workspace)).count
        let count = "\(windows.count) windows" + (workspaces > 1 ? " on \(workspaces) workspaces" : "")
        guard let window = windows.first(where: { $0.windowId == marked }) else { return count }
        return count + " · " + window.caption + (workspaces > 1 ? " · ws \(window.workspace)" : "")
    }

    private static func lane(_ visit: Visit) -> Lane {
        if let missing = visit.missingApp?.notFound { return .notice(name: missing.name, reason: missing.reason) }
        if let strip = visit.strip, let first = visit.stripWindows.first {
            return .app(name: first.appName, bundleId: strip.app ?? "", summary: Self.summary(visit.stripWindows, marked: strip.marked))
        }
        if let marked = visit.marking?.marked, let ringed = visit.model.windowsInGridOrder.first(where: { $0.windowId == marked }) {
            return .app(name: ringed.appName, bundleId: ringed.bundleId, summary: ringed.caption + " · ws " + ringed.workspace)
        }
        if visit.query.isEmpty { return .keys }
        return .query(visit.query, miss: visit.matches.isEmpty && visit.query.trimmingCharacters(in: .whitespaces).count >= OverviewModel.minQueryLength)
    }
}
