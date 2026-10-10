import CoreGraphics
import Foundation

public enum WorkspaceTree {
    public static func order(_ rects: [(Int, CGRect)]) -> [Int] {
        guard rects.count > 1 else { return rects.map(\.0) }
        for (lo, hi) in [(\CGRect.minX, \CGRect.maxX), (\.minY, \.maxY)] {
            if let parts = cut(rects, lo, hi) { return parts.flatMap { order($0) } }
        }
        return rects.map(\.0)
    }

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
