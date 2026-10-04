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

    /// One line of the legend under the strip: the window's key, its caption, the workspace it
    /// is on when the app spans more than one, and whether it is the marked one.
    public struct LegendRow: Equatable, Sendable {
        public let key: String?
        public let title: String
        public let workspace: String?
        public let marked: Bool
    }

    /// The legend: where a window is told apart when its picture cannot be. The cards stay true
    /// to AeroSpace's geometry, which on a crowded workspace is slivers under slivers; the legend
    /// is readable whatever AeroSpace did, and the key on each line is the pick.
    public static func legend(_ windows: [ParsedWindow], marked: Int?) -> [LegendRow] {
        let several = Set(windows.map(\.workspace)).count > 1
        return windows.enumerated().map { i, w in
            LegendRow(key: keyLabel(i), title: w.window.caption, workspace: several ? w.workspace : nil,
                      marked: w.window.windowId == marked)
        }
    }

    /// What the strip says after the app's name: how many windows, and on how many workspaces when more than one.
    public static func summary(windows: Int, workspaces: Int) -> String {
        "\(windows) windows" + (workspaces > 1 ? " on \(workspaces) workspaces" : "")
    }

    /// One step from `index` among `count`, wrapping; with no marking (-1) from the near end;
    /// -1 when there is nothing to step onto.
    public static func stepIndex(_ index: Int, count: Int, direction: Int) -> Int {
        guard count > 0 else { return -1 }
        guard index >= 0 else { return direction < 0 ? count - 1 : 0 }
        return ((index + direction) % count + count) % count
    }

    /// Where the marking opens: on the window after the one you are in, so two windows are the
    /// key and Enter; from outside the app on its window used last (`recent`, most recent
    /// first), as ⌘Tab goes back to it, or on the first when none is known.
    public static func start(origin: Int?, ids: [Int], recent: [Int] = []) -> Int? {
        guard !ids.isEmpty else { return nil }
        if origin.map({ !ids.contains($0) }) ?? true, let last = recent.first(where: ids.contains) { return last }
        let at = origin.flatMap { ids.firstIndex(of: $0) } ?? -1
        return ids[stepIndex(at, count: ids.count, direction: 1)]
    }

    /// The marking after the windows changed: it stays on its window, or goes to the one that
    /// took the closed window's place.
    public static func keepSelection(_ id: Int?, lastIndex: Int, ids: [Int]) -> Int? {
        guard !ids.isEmpty else { return nil }
        if let id, ids.contains(id) { return id }
        return ids[max(0, min(ids.count - 1, lastIndex))]
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
