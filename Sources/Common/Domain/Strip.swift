import Foundation

/// The strip this visit, as a value: whose windows, the marking, and where the row centres.
/// Every change is a new strip, so a change is one assignment
/// and nothing is ever half-updated; the store only holds the current one. The app is named by
/// bundle id, so a window of another app whose title happens to name this one is not in it.
/// A key's move of the strip's marking, -1 back or up, 1 on or down; or to a card by its place.
public enum StripMove: Equatable, Sendable { case window(Int), row(Int), workspace(Int), card(Int) }

public struct Strip: Equatable, Sendable {
    public let bundleId: String
    public let marked: Int?
    /// The window the carousel centres on: the marking, as keys move it. Pointing marks
    /// without moving it, or the row would slide another window under a hand that had not
    /// moved (krn.overview: "Keys move the centre; the pointer does not").
    public let centre: Int?

    /// Opened on the window after the one you are in (`AppStripModel.start`), the centre on it.
    public static func opened(_ bundleId: String, origin: Int?, ids: [Int], recent: [Int]) -> Strip {
        let first = AppStripModel.start(origin: origin, ids: ids, recent: recent)
        return Strip(bundleId: bundleId, marked: first, centre: first)
    }

    /// The pointer marks; the centre stays where the keys left it.
    public func marking(_ id: Int) -> Strip { Strip(bundleId: bundleId, marked: id, centre: centre) }

    /// The keys move the marking, the centre with it: a window along `ids`, wrapping (Tab, ← and
    /// →, the app key again); a row on its card, by the cards' `frames` as drawn (↑ and ↓); or
    /// to the next or previous workspace's first window (⌘→ and ⌘←), wrapping, or a named one's
    /// (its name, the one on its card). `card` says which
    /// card, numbered from 0, a window is on.
    public func moved(_ move: StripMove, ids: [Int], card: (Int) -> Int?, frames: [[Int: CGRect]] = []) -> Strip {
        let to: Int?
        switch move {
        case .window(let d):
            to = AppStripModel.stepIndex(marked.flatMap { ids.firstIndex(of: $0) } ?? -1, count: ids.count, direction: d).map { ids[$0] }
        case .row(let d):
            to = marked.flatMap { id in frames.lazy.compactMap { AppStripModel.vertical(from: id, direction: d, frames: $0) }.first }
        case .workspace(let d):
            let cards = (ids.compactMap(card).max() ?? -1) + 1
            to = ids.first { card($0) == ((marked.flatMap(card) ?? 0) + d + cards) % max(1, cards) }
        case .card(let at):
            to = ids.first { card($0) == at }
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
