import Foundation

/// A key's move of a marking, the strip's or the map's, -1 back, left or up, 1 on, right or down: a
/// window in order (← →, the app key again), a row (↑ ↓), a workspace along, above or below (⌘ and
/// an arrow), or to a card by its place.
public enum StripMove: Hashable, Sendable { case window(Int), row(Int), workspace(Int), workspaceRow(Int), card(Int) }

/// The marking this visit, as a value: the map's, or a strip's — `app` is then whose windows it
/// has, by bundle id, so a window of another app whose title happens to name this one is not in it.
public struct Strip: Equatable, Sendable {
    public let app: String?
    public let marked: Int?
    /// The window the carousel centres on: the marking, as keys move it.
    public let centre: Int?

    public init(app: String?, marked: Int?, centre: Int?) { (self.app, self.marked, self.centre) = (app, marked, centre) }

    /// A strip, opened on the window after the one you are in (`AppStripModel.start`), the centre on it.
    public static func opened(_ app: String, origin: Int?, ids: [Int], recent: [Int]) -> Strip {
        let first = AppStripModel.start(origin: origin, ids: ids, recent: recent)
        return Strip(app: app, marked: first, centre: first)
    }

    /// Whether `window` is one of this marking's: a strip's app's, or any at all for the map's.
    public func owns(_ window: WindowInfo) -> Bool { app.map { $0 == window.bundleId } ?? true }

    /// The pointer marks; the centre stays where the keys left it.
    public func marking(_ id: Int) -> Strip { Strip(app: app, marked: id, centre: centre) }

    /// The keys move the marking, the centre with it: a window along `ids`, wrapping; a row through
    /// the `cards` as drawn (`GridWalk`); a workspace along, above or below; or a named card.
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

    /// AeroSpace moved the focus.
    public func following(_ focused: WindowInfo?) -> Strip? { focused?.bundleId == app ? self : nil }

    /// After the windows changed: the marking stays on its window and the centre where it was —
    /// AeroSpace's churn must not slide the row under a still hand.
    public func kept(before: [Int], after: [Int]) -> Strip? {
        guard let marked, let at = before.firstIndex(of: marked), !after.contains(marked) else { return self }
        return after.dropFirst(max(0, min(after.count - 1, at))).first.map { Strip(app: app, marked: $0, centre: $0) }
    }
}
