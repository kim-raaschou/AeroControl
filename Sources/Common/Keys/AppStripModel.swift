import CoreGraphics
import Foundation

public enum AppStripModel {
    public static func keyLabel(_ index: Int) -> String? {
        FilterKey.windowKeys.indices.contains(index) ? "⌘\(FilterKey.windowKeys[index])" : nil
    }

    public static func summary(_ windows: [ParsedWindow], marked: Int?) -> String {
        let workspaces = Set(windows.map(\.workspace)).count
        let count = "\(windows.count) windows" + (workspaces > 1 ? " on \(workspaces) workspaces" : "")
        guard let window = windows.first(where: { $0.window.windowId == marked }) else { return count }
        return count + " · " + window.window.caption + (workspaces > 1 ? " · ws \(window.workspace)" : "")
    }

    public static func stepIndex(_ index: Int, count: Int, direction: Int) -> Int? {
        guard count > 0 else { return nil }
        return ((max(index, direction < 0 ? 0 : -1) + direction) % count + count) % count
    }

    public static func start(origin: Int?, ids: [Int], recent: [Int] = []) -> Int? {
        if let last = recent.first(where: { ids.contains($0) && $0 != origin }) { return last }
        return stepIndex(origin.flatMap { ids.firstIndex(of: $0) } ?? -1, count: ids.count, direction: 1).map { ids[$0] }
    }

    public enum Action: Equatable, Sendable {
        case none
        case move(StripMove)
        case commit(Int)
        case cancel
    }

    public static func action(for key: FilterKey, ids: [Int], marked: Int?, workspaces: [String] = []) -> Action {
        switch key {
        case .escape: return .cancel
        case .enter: return marked.map { .commit($0) } ?? .none
        case .move(let move): return .move(move)
        case .commandKey(let n):
            return ids.prefix(FilterKey.windowKeys.count).indices.contains(n - 1) ? .commit(ids[n - 1]) : .none
        case .character(let c): return FilterKey.workspaceNamed(String(c)).flatMap(workspaces.firstIndex).map { .move(.card($0)) } ?? .none
        case .backspace, .moveToWorkspace, .help: return .none
        }
    }
}
