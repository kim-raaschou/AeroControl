import CoreGraphics
import Foundation

/// The strip's rules, ported from krn.overview's `AppStripModel.js`: which window the marking
/// opens on, how it steps, where it goes when its window closes, how tall the cards are, how
/// the row runs round when it does not fit, how a window is framed, and what a key does. One
/// difference by decision: the marking only chooses — Enter, a key or a click focuses —
/// so stepping never switches AeroSpace's workspace behind the strip.
public enum AppStripModel {
    /// The keys windows carry, in order: ⌘1–⌘9 as macOS numbers tabs, then ⌘a–⌘f, fifteen in all.
    public static let keys: [Character] = Array("123456789abcdef")

    /// The key on the window at `index`, nil past the fifteenth.
    public static func keyLabel(_ index: Int) -> String? {
        keys.indices.contains(index) ? "⌘\(keys[index])" : nil
    }

    /// What the strip's one line says after the app's name: how many windows, on how many
    /// workspaces when more than one, and the marked window's title — what Enter picks, with its
    /// workspace when there are several. Its key is on its card. Pointing marks, so a picture too
    /// small to read is read here by pointing at it.
    public static func summary(_ windows: [ParsedWindow], marked: Int?) -> String {
        let workspaces = Set(windows.map(\.workspace)).count
        let count = "\(windows.count) windows" + (workspaces > 1 ? " on \(workspaces) workspaces" : "")
        guard let window = windows.first(where: { $0.window.windowId == marked }) else { return count }
        return count + " · " + window.window.caption + (workspaces > 1 ? " · ws \(window.workspace)" : "")
    }

    /// One step from `index` among `count`, wrapping; with no marking (-1) from the near end;
    /// nil when there is nothing to step onto.
    public static func stepIndex(_ index: Int, count: Int, direction: Int) -> Int? {
        guard count > 0 else { return nil }
        return ((max(index, direction < 0 ? 0 : -1) + direction) % count + count) % count
    }

    /// Where the marking opens: on the app's window you used last other than the one you are in
    /// (`recent`, most recent first), as ⌘` and ⌘Tab go back to it, so the key and Enter are
    /// the way back; known none, on the window after the one you are in, or the first.
    public static func start(origin: Int?, ids: [Int], recent: [Int] = []) -> Int? {
        if let last = recent.first(where: { ids.contains($0) && $0 != origin }) { return last }
        return stepIndex(origin.flatMap { ids.firstIndex(of: $0) } ?? -1, count: ids.count, direction: 1).map { ids[$0] }
    }

    /// The most of the panel's height a strip card takes: one card, an app all on one workspace,
    /// all but fills it.
    public static let tallest: CGFloat = 0.85
    /// The most when the app is on more than one workspace: the strip is a view over several.
    public static let tallestOfSeveral: CGFloat = 0.33
    /// How many cards the view holds when the app is on more than one workspace, if the ceiling
    /// allows: three whole in the middle and, with more, a dimmed quarter of the next at each
    /// edge, so the row shows that it goes on.
    public static let seen: CGFloat = 3.5

    /// How tall the strip's cards are: one card fills the view's width, more each take a
    /// `seen`th of it, every card in its screen's shape (`aspect`) inside its `chrome`; never
    /// more than `tallest` of the panel, or `tallestOfSeveral` for several.
    public static func cardHeight(view: CGFloat, cards: Int, aspect: CGFloat, chrome: CGFloat, panelHeight: CGFloat) -> CGFloat {
        let each = view / min(CGFloat(max(1, cards)), seen) - chrome
        return min((panelHeight * (cards > 1 ? tallestOfSeveral : tallest)).rounded(), (each / max(0.01, aspect)).rounded(.down))
    }

    /// A card's place on the unrolled row.
    public struct Span: Equatable, Sendable {
        public let x: CGFloat
        public let width: CGFloat
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Move the marking (`Strip.moved`).
        case move(StripMove)
        /// Focus this window and close.
        case commit(Int)
        /// Close, back on the window you came from.
        case cancel
    }

    /// What a key does in the strip. There is no typing here, search belongs to the map: ⌘ and
    /// a window's key goes straight to that window, and a workspace's name, of the `workspaces`
    /// the strip shows, to that workspace — 0 to 10, the key in its place on the keyboard.
    public static func action(for key: FilterKey, ids: [Int], marked: Int?, workspaces: [String] = []) -> Action {
        switch key {
        case .escape: return .cancel
        case .enter: return marked.map { .commit($0) } ?? .none
        case .move(let move): return .move(move)
        case .commandKey(let n):
            return ids.prefix(keys.count).indices.contains(n - 1) ? .commit(ids[n - 1]) : .none
        case .character(let c): return workspaces.firstIndex(of: ["0": "10"][String(c)] ?? String(c)).map { .move(.card($0)) } ?? .none
        case .backspace: return .none
        }
    }
}
