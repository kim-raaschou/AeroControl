import Foundation

public enum StripMove: Hashable, Sendable { case window(Int), row(Int), workspace(Int), workspaceRow(Int), card(Int) }

public struct Strip: Equatable, Sendable {
    public let app: String?
    public let marked: Int?
    public let centre: Int?

    public init(app: String?, marked: Int?, centre: Int?) { (self.app, self.marked, self.centre) = (app, marked, centre) }

    public static func opened(_ app: String, origin: Int?, ids: [Int], recent: [Int]) -> Strip {
        let first = AppStripModel.start(origin: origin, ids: ids, recent: recent)
        return Strip(app: app, marked: first, centre: first)
    }

    public func owns(_ window: WindowInfo) -> Bool { app.map { $0 == window.bundleId } ?? true }

    public func marking(_ id: Int) -> Strip { Strip(app: app, marked: id, centre: centre) }

    public func moved(_ move: StripMove, ids: [Int], card: (Int) -> Int?, cards: [GridWalk.Card] = []) -> Strip {
        let frames = cards.reduce(into: [Int: CGRect]()) { $0.merge($1.windows) { a, _ in a } }
        let to: Int?
        switch move {
        case .window(let d): to = AppStripModel.stepIndex(marked.flatMap { ids.firstIndex(of: $0) } ?? -1, count: ids.count, direction: d).map { ids[$0] }
        case .row(let d): to = marked.flatMap { GridWalk.step(from: $0, rows: d, frames: frames) }
        case .workspace(let d):
            let held = Array(Set(ids.compactMap(card))).sorted()
            to = AppStripModel.stepIndex(held.firstIndex { $0 == marked.flatMap(card) } ?? -1, count: held.count, direction: d).flatMap { at in ids.first { card($0) == held[at] } }
        case .workspaceRow(let d): to = marked.flatMap { GridWalk.cardRow(from: $0, direction: d, cards: cards) }
        case .card(let at): to = ids.first { card($0) == at }
        }
        return to.map { Strip(app: app, marked: $0, centre: $0) } ?? self
    }

    public func following(_ focused: WindowInfo?) -> Strip? { focused?.bundleId == app ? self : nil }

    public func kept(before: [Int], after: [Int]) -> Strip? {
        guard let marked, let at = before.firstIndex(of: marked), !after.contains(marked) else { return self }
        return after.dropFirst(max(0, min(after.count - 1, at))).first.map { Strip(app: app, marked: $0, centre: $0) }
    }
}
