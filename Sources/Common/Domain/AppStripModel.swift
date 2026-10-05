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
    /// -1 when there is nothing to step onto.
    public static func stepIndex(_ index: Int, count: Int, direction: Int) -> Int {
        guard count > 0 else { return -1 }
        guard index >= 0 else { return direction < 0 ? count - 1 : 0 }
        return ((index + direction) % count + count) % count
    }

    /// Where the marking opens: on the app's window you used last other than the one you are in
    /// (`recent`, most recent first), as ⌘` and ⌘Tab go back to it, so the key and Enter are
    /// the way back; known none, on the window after the one you are in, or the first.
    public static func start(origin: Int?, ids: [Int], recent: [Int] = []) -> Int? {
        guard !ids.isEmpty else { return nil }
        if let last = recent.first(where: { ids.contains($0) && $0 != origin }) { return last }
        let at = origin.flatMap { ids.firstIndex(of: $0) } ?? -1
        return ids[stepIndex(at, count: ids.count, direction: 1)]
    }

    /// How tall the strip's cards are: as tall as `width` allows for cards whose shapes add up
    /// to `sumAspect`, never more than half the panel and never less than a fifth.
    public static func cardHeight(width: CGFloat, gaps: CGFloat, sumAspect: CGFloat, panelHeight: CGFloat) -> CGFloat {
        let most = (panelHeight * 0.5).rounded(), least = (panelHeight * 0.2).rounded()
        return max(least, min(most, ((width - gaps) / max(0.01, sumAspect)).rounded(.down)))
    }

    /// A card's place on the unrolled row.
    public struct Span: Equatable, Sendable {
        public let x: CGFloat
        public let width: CGFloat
    }

    public enum Action: Equatable, Sendable {
        case none
        /// Move the marking this many windows, wrapping.
        case step(Int)
        /// Focus this window and close.
        case commit(Int)
        /// Close, back on the window you came from.
        case cancel
    }

    /// What a key does in the strip. There is no typing here, search belongs to the map: ⌘ and
    /// a window's key goes straight to that window.
    public static func action(for key: FilterKey, ids: [Int], marked: Int?) -> Action {
        switch key {
        case .escape: return .cancel
        case .enter: return marked.map { .commit($0) } ?? .none
        case .next: return .step(1)
        case .previous: return .step(-1)
        case .commandKey(let n):
            return n >= 1 && n <= min(keys.count, ids.count) ? .commit(ids[n - 1]) : .none
        case .character, .backspace: return .none
        }
    }
}
