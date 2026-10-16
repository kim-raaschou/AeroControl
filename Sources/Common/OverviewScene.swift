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
        public let origin: Bool
        public let ghost: Bool
        public let lane: CGFloat
        public let stacking: Double

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

    public init(_ visit: Visit, error: String?, available: CGSize, screens: [Int: CGRect], frames: [Int: CGRect]) {
        let model = visit.model, ring = visit.ringWindowId, usable = AeroControlLayout.usable(available)
        (size, ringed, lane) = (usable, ring, Self.lane(visit, error: error))
        let shown: [WorkspaceInfo], laid: [AeroControlLayout.LaidCard], offset: CGFloat, filtering: Bool
        if error != nil || model.workspaces.isEmpty || visit.missingApp != nil {
            (body, shown, laid, offset, filtering, held) = (.nothing, [], [], 0, false, nil)
        } else if let strip = visit.strip, !visit.stripWindows.isEmpty {
            shown = visit.stripWorkspaces
            laid = AeroControlLayout.stripLayout(groups: shown, bundleId: strip.app ?? "", frames: frames, screens: screens, available: available)
            held = laid.firstIndex { c in strip.centre.map { c.frames[$0] != nil } ?? false }
            (body, filtering, offset) = (.strip, false, AeroControlLayout.stripOffset(laid, held: held ?? 0, viewWidth: usable.width))
        } else {
            let filtered = model.workspaces(holding: visit.matches)
            (body, held, offset, filtering) = (.map, nil, 0, !filtered.isEmpty)
            shown = filtering ? filtered : model.workspaces
            laid = AeroControlLayout.mapLayout(workspaces: shown, frames: frames, screens: screens, available: available, filtering: filtering)
        }
        let captions = body == .map
        grid = laid.map(\.grid)
        cards = zip(shown, laid).map { ws, c in
            let frame = c.frame.offsetBy(dx: offset, dy: 0)
            let tiles = ws.windows.compactMap { w in c.frames[w.windowId].map { f in
                Tile(window: w, frame: f, ringed: w.windowId == ring, origin: w.windowId != ring && w.windowId == model.focusedWindowId,
                     ghost: c.ghosts.contains(w.windowId),
                     lane: captions && (filtering || frames[w.windowId] == nil) && f.height >= AeroControlLayout.captionLane + AeroControlLayout.minPictureHeight ? AeroControlLayout.captionLane : 0,
                     stacking: c.ghosts.contains(w.windowId) ? 2 : w.windowId == model.focusedWindowId ? 1 : 0)
            } }
            return Card(workspace: ws, frame: frame, focused: ws.name == model.focusedWorkspace, visible: ws.isVisible,
                        monitor: model.spansMonitors && !ws.monitorShortName.isEmpty ? ws.monitorShortName : nil, ringed: ring == ws.standIn,
                        cut: frame.minX < 0 || frame.maxX > usable.width, tiles: tiles)
        }
    }

    private static func summary(_ windows: [WindowInfo], marked: Int?) -> String {
        let workspaces = Set(windows.map(\.workspace)).count
        let count = "\(windows.count) windows" + (workspaces > 1 ? " on \(workspaces) workspaces" : "")
        guard let window = windows.first(where: { $0.windowId == marked }), workspaces > 1 else { return count }
        return count + " · ws \(window.workspace)"
    }

    private static func lane(_ visit: Visit, error: String?) -> Lane {
        if let error { return .notice(name: "Load error", reason: error) }
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
