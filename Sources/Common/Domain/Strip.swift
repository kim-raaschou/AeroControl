import Foundation

/// The strip this visit, as a value: whose windows, the marking, where the carousel centres,
/// and how many turns it has taken. Every change is a new strip, so a change is one assignment
/// and nothing is ever half-updated; the store only holds the current one. The app is named by
/// bundle id, so a window of another app whose title happens to name this one is not in it.
public struct Strip: Equatable, Sendable {
    public let bundleId: String
    public let marked: Int?
    /// The window the carousel centres on: the marking, as keys move it. Pointing marks
    /// without moving it, or the row would slide another window under a hand that had not
    /// moved (krn.overview: "Keys move the centre; the pointer does not").
    public let centre: Int?
    /// How many times the keys have taken the ring round past its last card, less the times
    /// back past its first: what keeps the carousel turning one way instead of jumping back.
    public let turns: Int

    /// Opened on the window after the one you are in (`AppStripModel.start`), the centre on it.
    public static func opened(_ bundleId: String, origin: Int?, ids: [Int], recent: [Int]) -> Strip {
        let first = AppStripModel.start(origin: origin, ids: ids, recent: recent)
        return Strip(bundleId: bundleId, marked: first, centre: first, turns: 0)
    }

    /// The pointer marks; the centre stays where the keys left it.
    public func marking(_ id: Int) -> Strip { Strip(bundleId: bundleId, marked: id, centre: centre, turns: turns) }

    /// One step along `ids`, wrapping. `card` says which card a window is on; a step that
    /// comes round past the last card forward, or the first backward, is a turn.
    public func stepped(_ direction: Int, ids: [Int], card: (Int) -> Int?) -> Strip {
        let at = AppStripModel.stepIndex(marked.flatMap { ids.firstIndex(of: $0) } ?? -1, count: ids.count, direction: direction)
        guard at >= 0 else { return self }
        var turns = self.turns
        if let from = centre.flatMap(card), let to = card(ids[at]) {
            if direction > 0, to < from { turns += 1 }
            if direction < 0, to > from { turns -= 1 }
        }
        return Strip(bundleId: bundleId, marked: ids[at], centre: ids[at], turns: turns)
    }

    /// AeroSpace moved the focus: to this app's window, or to none, nothing changes. To another
    /// app's window among several of that app, the strip turns to that app, marked there, as
    /// the app's key would open it. To an app of one window there is nothing to choose: nil, the
    /// strip is over.
    public func following(_ focused: WindowInfo?, among windows: [WindowInfo]) -> Strip? {
        guard let focused, focused.bundleId != bundleId else { return self }
        guard windows.count(where: { $0.bundleId == focused.bundleId }) > 1 else { return nil }
        return Strip(bundleId: focused.bundleId, marked: focused.windowId, centre: focused.windowId, turns: 0)
    }

    /// After the windows changed: the marking stays on its window and the centre where it was —
    /// AeroSpace's churn must not turn the carousel under a still hand. A closed marked window
    /// hands the marking, and the centre, to the one that took its place. With none left there
    /// is nothing to choose: nil, the strip is over.
    public func kept(before: [Int], after: [Int]) -> Strip? {
        if let marked, after.contains(marked) { return self }
        guard !after.isEmpty else { return nil }
        let now = after[min(after.count - 1, marked.flatMap { before.firstIndex(of: $0) } ?? 0)]
        return Strip(bundleId: bundleId, marked: now, centre: now, turns: turns)
    }
}
