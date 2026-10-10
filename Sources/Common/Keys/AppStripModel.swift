import CoreGraphics
import Foundation

/// The strip's rules, ported from krn.overview's `AppStripModel.js`: which window the marking opens
/// on, how it steps, where it goes when its window closes, how tall the cards are, how the row runs
/// round when it does not fit, how a window is framed, and what a key does.
public enum AppStripModel {
    /// The key on the window at `index` (`FilterKey.windowKeys`), nil past the fifteenth.
    public static func keyLabel(_ index: Int) -> String? {
        FilterKey.windowKeys.indices.contains(index) ? "⌘\(FilterKey.windowKeys[index])" : nil
    }

    /// What the strip's one line says after the app's name: how many windows, on how many
    /// workspaces when more than one, and the marked window's title — what Enter picks, with its
    /// workspace when there are several.
    public static func summary(_ windows: [ParsedWindow], marked: Int?) -> String {
        let workspaces = Set(windows.map(\.workspace)).count
        let count = "\(windows.count) windows" + (workspaces > 1 ? " on \(workspaces) workspaces" : "")
        guard let window = windows.first(where: { $0.window.windowId == marked }) else { return count }
        return count + " · " + window.window.caption + (workspaces > 1 ? " · ws \(window.workspace)" : "")
    }

    /// One step from `index` among `count`, wrapping; with no marking (-1) from the near end; nil
    /// when there is nothing to step onto.
    public static func stepIndex(_ index: Int, count: Int, direction: Int) -> Int? {
        guard count > 0 else { return nil }
        return ((max(index, direction < 0 ? 0 : -1) + direction) % count + count) % count
    }

    /// Where the marking opens: on the app's window you used last other than the one you are in
    /// (`recent`, most recent first), as ⌘` and ⌘Tab go back to it, so the key and Enter are the
    /// way back; known none, on the window after the one you are in, or the first.
    public static func start(origin: Int?, ids: [Int], recent: [Int] = []) -> Int? {
        if let last = recent.first(where: { ids.contains($0) && $0 != origin }) { return last }
        return stepIndex(origin.flatMap { ids.firstIndex(of: $0) } ?? -1, count: ids.count, direction: 1).map { ids[$0] }
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

    /// What a key does in the strip.
    public static func action(for key: FilterKey, ids: [Int], marked: Int?, workspaces: [String] = []) -> Action {
        switch key {
        case .escape: return .cancel
        case .enter: return marked.map { .commit($0) } ?? .none
        case .move(let move): return .move(move)
        case .commandKey(let n):
            return ids.prefix(FilterKey.windowKeys.count).indices.contains(n - 1) ? .commit(ids[n - 1]) : .none
        case .character(let c): return FilterKey.workspaceNamed(String(c)).flatMap(workspaces.firstIndex).map { .move(.card($0)) } ?? .none
        case .backspace, .moveToWorkspace: return .none
        }
    }
}
