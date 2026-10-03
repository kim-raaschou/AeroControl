import CoreGraphics
import Foundation

/// The layout's own order of a workspace's windows, read from AeroSpace's rects
/// (`WindowInfo.layoutRect`): what the ring, the keys and the strip walk. Nothing here infers
/// a layout — the reconstruction from window sizes was removed on 2026-10-03, since it guessed
/// what AeroSpace had not said, and the rects say it.
public enum WorkspaceTree {
    public enum Axis: Equatable, Sendable {
        case horizontal, vertical
    }

    /// The layout's own order from AeroSpace's rects: the rects are cut along lines that cross no
    /// window, columns before rows, and the parts read left to right and top to bottom, each
    /// part the same way in turn. For a tiling layout that is the tree's order — a column is
    /// read top to bottom before the window beside it. Rects that overlap, an accordion's, keep
    /// the order they came in.
    public static func order(_ rects: [(Int, CGRect)]) -> [Int] {
        guard rects.count > 1 else { return rects.map(\.0) }
        for axis in [Axis.horizontal, .vertical] {
            if let parts = cut(rects, along: axis) { return parts.flatMap { order($0) } }
        }
        return rects.map(\.0)
    }

    /// The rects in runs separated by gaps along `axis`, each run in the order the rects came;
    /// nil when there is no such gap.
    private static func cut(_ rects: [(Int, CGRect)], along axis: Axis) -> [[(Int, CGRect)]]? {
        func lo(_ r: CGRect) -> CGFloat { axis == .horizontal ? r.minX : r.minY }
        func hi(_ r: CGRect) -> CGFloat { axis == .horizontal ? r.maxX : r.maxY }
        let indexed = rects.enumerated().sorted { lo($0.element.1) < lo($1.element.1) }
        var runs: [[(offset: Int, element: (Int, CGRect))]] = [[indexed[0]]]
        var end = hi(indexed[0].element.1)
        for item in indexed.dropFirst() {
            if lo(item.element.1) >= end - 2 { runs.append([item]) } else { runs[runs.count - 1].append(item) }
            end = max(end, hi(item.element.1))
        }
        guard runs.count > 1 else { return nil }
        return runs.map { run in run.sorted { $0.offset < $1.offset }.map(\.element) }
    }
}
