import CoreGraphics
import Foundation

/// The workspace cards on the screen: one identical, screen-shaped cell per workspace in a lattice,
/// as GNOME Shell and KWin lay their overviews out.
public enum CardGrid {
    /// `count` cells in `box`, `gap` apart, each cell's inner box — the cell less `chrome`, what a
    /// card spends on header and padding — of `cellRatio` (width / height), so a screen drawn into
    /// it fills it.
    public static func lattice(count n: Int, in box: CGSize, cellRatio: CGFloat, gap: CGFloat, chrome: CGSize = .zero) -> [CGRect] {
        guard n > 0 else { return [] }
        var best: (area: CGFloat, rows: Int, columns: Int, cell: CGSize)?
        for r in 1...n {
            let c = (n + r - 1) / r
            let h = (box.height - gap * CGFloat(r - 1)) / CGFloat(r)
            let wByHeight = (h - chrome.height) * cellRatio + chrome.width
            let w = min((box.width - gap * CGFloat(c - 1)) / CGFloat(c), wByHeight)
            guard w > chrome.width else { continue }
            let cell = CGSize(width: w, height: (w - chrome.width) / cellRatio + chrome.height)
            // The largest cell; among equals, the fewest holes.
            let area = cell.width * cell.height - CGFloat(r * c - n) * 0.001
            if best == nil || area > best!.area { best = (area, r, c, cell) }
        }
        guard let b = best else { return Array(repeating: .zero, count: n) }
        let cell = CGSize(width: b.cell.width.rounded(.down), height: b.cell.height.rounded(.down))
        let block = CGSize(width: CGFloat(b.columns) * cell.width + CGFloat(b.columns - 1) * gap,
                           height: CGFloat(b.rows) * cell.height + CGFloat(b.rows - 1) * gap)
        let origin = CGPoint(x: ((box.width - block.width) / 2).rounded(.down), y: ((box.height - block.height) / 2).rounded(.down))
        return (0..<n).map { i in
            CGRect(origin: CGPoint(x: origin.x + CGFloat(i % b.columns) * (cell.width + gap),
                                   y: origin.y + CGFloat(i / b.columns) * (cell.height + gap)), size: cell)
        }
    }
}
