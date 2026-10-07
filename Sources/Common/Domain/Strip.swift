import Foundation

/// The strip this visit, as a value: whose windows, the marking, and where the row centres.
/// Every change is a new strip, so a change is one assignment
/// and nothing is ever half-updated; the store only holds the current one. The app is named by
/// bundle id, so a window of another app whose title happens to name this one is not in it.
/// A key's move of a marking, the strip's or the map's, -1 back, left or up, 1 on, right or
/// down: a window in order (← →, the app key again), a row (↑ ↓), a workspace along, above or
/// below (⌘ and an arrow), or to a card by its place.
public enum StripMove: Hashable, Sendable { case window(Int), row(Int), workspace(Int), workspaceRow(Int), card(Int) }

public struct Strip: Equatable, Sendable {
    public let bundleId: String
    public let marked: Int?
    /// The window the carousel centres on: the marking, as keys move it. Pointing marks
    /// without moving it, or the row would slide another window under a hand that had not
    /// moved (krn.overview: "Keys move the centre; the pointer does not").
    public let centre: Int?

    /// A marking as it stands; the map walks its own with the strip's rules (`moved`).
    public init(bundleId: String, marked: Int?, centre: Int?) { (self.bundleId, self.marked, self.centre) = (bundleId, marked, centre) }

    /// Opened on the window after the one you are in (`AppStripModel.start`), the centre on it.
    public static func opened(_ bundleId: String, origin: Int?, ids: [Int], recent: [Int]) -> Strip {
        let first = AppStripModel.start(origin: origin, ids: ids, recent: recent)
        return Strip(bundleId: bundleId, marked: first, centre: first)
    }

    /// The pointer marks; the centre stays where the keys left it.
    public func marking(_ id: Int) -> Strip { Strip(bundleId: bundleId, marked: id, centre: centre) }

    /// The keys move the marking, the centre with it — on the strip and, the same way, on the
    /// map: a window along `ids`, wrapping (← →, the app key again), `ids` running through one
    /// workspace's windows and on to the next's; straight up or down through the `cards` as
    /// drawn (`GridWalk`: ↑ ↓); to
    /// the next or previous workspace's first window (⌘→ and ⌘←), wrapping past those with none,
    /// or the one above or below's as drawn (⌘↑ and ⌘↓; the strip has no row above or below),
    /// or a named one's (its name, the one on its card). `card` numbers a window's workspace from
    /// 0; the jumps go by it alone, so they work before anything is drawn.
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
        return to.map { Strip(bundleId: bundleId, marked: $0, centre: $0) } ?? self
    }

    /// AeroSpace moved the focus. Within this app the strip stands. Anywhere else — another app,
    /// an empty workspace — the choice was made with AeroSpace: nil, the strip is over and you
    /// are where AeroSpace put you. A strip is only ever opened by its app's key.
    public func following(_ focused: WindowInfo?) -> Strip? { focused?.bundleId == bundleId ? self : nil }

    /// After the windows changed: the marking stays on its window and the centre where it was —
    /// AeroSpace's churn must not slide the row under a still hand. A closed marked window
    /// hands the marking, and the centre, to the one that took its place. With none left there
    /// is nothing to choose: nil, the strip is over.
    public func kept(before: [Int], after: [Int]) -> Strip? {
        if let marked, after.contains(marked) { return self }
        guard !after.isEmpty else { return nil }
        let now = after[min(after.count - 1, marked.flatMap { before.firstIndex(of: $0) } ?? 0)]
        return Strip(bundleId: bundleId, marked: now, centre: now)
    }
}
