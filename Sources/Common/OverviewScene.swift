import CoreGraphics
import Foundation

public struct OverviewScene: Sendable {
    public enum Body: Equatable, Sendable { case nothing, map, strip }

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
        public let focused: Bool
        public let ghost: Bool
        public let lane: CGFloat

        public var origin: Bool { focused && !ringed }
        public var stacking: Double { ghost ? 2 : focused ? 1 : 0 }
        public var picture: CGSize { CGSize(width: frame.width, height: frame.height - lane) }
    }

    public struct Card: Equatable, Sendable {
        public let workspace: WorkspaceInfo
        public let frame: CGRect
        public let focused: Bool
        public let visible: Bool
        public let monitor: String?
        public let ringed: Bool
        public let cut: Bool
        public let tiles: [Tile]
        public let named: WindowInfo?
    }

    public let body: Body
    public let size: CGSize
    public let cards: [Card]
    public let lane: Lane
    public let ringed: Int?
    public let held: Int?
    public let grid: [GridWalk.Card]

    public func pictureSizes(scale: CGFloat) -> [Int: CGSize] {
        Dictionary(cards.flatMap(\.tiles).map { ($0.window.windowId, CGSize(width: $0.picture.width * scale, height: $0.picture.height * scale)) }) { $1 }
    }

    public init(_ visit: Visit, available: CGSize, screens: [Int: CGRect], frames: [Int: CGRect]) {
        let model = visit.model, ring = visit.ringWindowId, filtering = !visit.matches.isEmpty, lane = Self.lane(visit)
        (size, ringed, self.lane) = (AeroControlLayout.usable(available), ring, lane)
        let shown: [WorkspaceInfo], laid: [AeroControlLayout.LaidCard]
        switch (lane, visit.strip) {
        case (.notice, _),
             _ where model.workspaces.isEmpty: (body, shown, laid, held) = (.nothing, [], [], nil)
        case (_, let strip?) where !visit.stripWindows.isEmpty:
            shown = visit.stripWorkspaces
            (laid, held) = AeroControlLayout.stripLayout(groups: shown, bundleId: strip.app ?? "", centre: strip.centre, frames: frames, screens: screens, available: available)
            body = .strip
        default:
            shown = filtering ? model.workspaces(holding: visit.matches) : model.workspaces
            laid = AeroControlLayout.mapLayout(workspaces: shown, frames: frames, screens: screens, available: available, filtering: filtering)
            (body, held) = (.map, nil)
        }
        grid = laid.map(\.grid)
        cards = zip(shown, laid).map { ws, c in
            let tiles = ws.windows.compactMap { w in c.frames[w.windowId].map { f in
                Tile(window: w, frame: f, ringed: w.windowId == ring, focused: w.windowId == model.focusedWindowId, ghost: c.ghosts.contains(w.windowId), lane: c.lanes[w.windowId] ?? 0)
            } }
            return Card(workspace: ws, frame: c.frame, focused: ws.name == model.focusedWorkspace, visible: ws.isVisible,
                        monitor: model.spansMonitors ? ws.monitorShortName : nil, ringed: ring == ws.standIn, cut: c.cut, tiles: tiles,
                        named: tiles.first(where: \.ringed)?.window)
        }
    }

    private static func summary(_ windows: [WindowInfo], marked: Int?) -> String {
        let workspaces = Set(windows.map(\.workspace)).count
        let count = "\(windows.count) windows" + (workspaces > 1 ? " on \(workspaces) workspaces" : "")
        guard let window = windows.first(where: { $0.windowId == marked }), workspaces > 1 else { return count }
        return count + " · ws \(window.workspace)"
    }

    private static func lane(_ visit: Visit) -> Lane {
        if let error = visit.error { return .notice(name: "Load error", reason: error) }
        if let missing = visit.missingApp?.notFound { return .notice(name: missing.name, reason: missing.reason) }
        if let strip = visit.strip, let first = visit.stripWindows.first {
            return .app(name: first.appName, bundleId: strip.app ?? "", summary: Self.summary(visit.stripWindows, marked: strip.marked))
        }
        if visit.query.isEmpty { return .keys }
        return .query(visit.query, miss: visit.matches.isEmpty && OverviewModel.isQuery(visit.query))
    }
}
