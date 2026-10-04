import CoreGraphics
import Foundation

/// The layout's own order of a workspace's windows, read from AeroSpace's rects
/// (`WindowInfo.layoutRect`): what the ring, the keys and the strip walk. Nothing here infers
/// a layout — the reconstruction from window sizes was removed on 2026-10-03, since it guessed
/// what AeroSpace had not said, and the rects say it.
public enum WorkspaceTree {
    /// The layout's own order from AeroSpace's rects: the rects are cut along lines that cross no
    /// window, columns before rows, and the parts read left to right and top to bottom, each
    /// part the same way in turn. For a tiling layout that is the tree's order — a column is
    /// read top to bottom before the window beside it. Rects that overlap, an accordion's, keep
    /// the order they came in.
    public static func order(_ rects: [(Int, CGRect)]) -> [Int] {
        guard rects.count > 1 else { return rects.map(\.0) }
        for (lo, hi) in [(\CGRect.minX, \CGRect.maxX), (\.minY, \.maxY)] {
            if let parts = cut(rects, lo, hi) { return parts.flatMap { order($0) } }
        }
        return rects.map(\.0)
    }

    /// The rects in runs separated by gaps along one axis, its edges `lo` and `hi`, each run in the
    /// order the rects came; nil when there is no such gap.
    private static func cut(_ rects: [(Int, CGRect)], _ lo: KeyPath<CGRect, CGFloat>, _ hi: KeyPath<CGRect, CGFloat>) -> [[(Int, CGRect)]]? {
        let indexed = rects.enumerated().sorted { $0.element.1[keyPath: lo] < $1.element.1[keyPath: lo] }
        var runs: [[(offset: Int, element: (Int, CGRect))]] = [[indexed[0]]]
        var end = indexed[0].element.1[keyPath: hi]
        for item in indexed.dropFirst() {
            if item.element.1[keyPath: lo] >= end - 2 { runs.append([item]) } else { runs[runs.count - 1].append(item) }
            end = max(end, item.element.1[keyPath: hi])
        }
        guard runs.count > 1 else { return nil }
        return runs.map { run in run.sorted { $0.offset < $1.offset }.map(\.element) }
    }
}
