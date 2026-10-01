import Testing
import Foundation
@testable import Common

// The tiling tree of a workspace, rebuilt from nothing but what AeroSpace and the window
// server give for a hidden workspace: the windows' sizes (which survive AeroSpace's parking),
// the root's axis, and — when AeroSpace can sort by dfs — the order. Sizes that do not add
// up give no tree at all; the card then falls back to tiles. Never half a tree.

fileprivate typealias T = WorkspaceTree
fileprivate func w(_ id: Int, _ width: CGFloat, _ height: CGFloat) -> T.Window { T.Window(id: id, size: CGSize(width: width, height: height)) }

/// The owner's workspace 7 on 2026-09-30, read from the window server while it was visible: a
/// column of four terminals at the left, one full-height terminal at the right. 1728 × 1084 is
/// the screen's visible frame; the windows sit inside 16-point outer gaps and 12-point inner ones.
fileprivate let ws7: [T.Window] = [w(8243, 842, 257), w(8240, 842, 251), w(3352, 842, 251), w(5022, 842, 257), w(8266, 842, 1052)]
private let screen = CGSize(width: 1728, height: 1084)

@Suite("WorkspaceTree.reconstruct")
struct WorkspaceTreeTests {
    @Test("workspace 7: four rows in a column, one window beside it, children as first listed")
    func ownersWorkspace7() {
        let tree = T.reconstruct(windows: ws7, root: .horizontal, area: screen)
        #expect(tree == .split(.horizontal, [.split(.vertical, [.window(8243), .window(8240), .window(3352), .window(5022)]), .window(8266)]))
        let tallFirst = T.reconstruct(windows: [ws7[4]] + ws7[0..<4], root: .horizontal, area: screen)
        #expect(tallFirst == .split(.horizontal, [.window(8266), .split(.vertical, [.window(8243), .window(8240), .window(3352), .window(5022)])]))
    }

    @Test("the mirror: a row of two above a full-width window under a vertical root")
    func verticalRoot() {
        let windows = [w(1, 842, 520), w(2, 842, 520), w(3, 1696, 520)]
        let tree = T.reconstruct(windows: windows, root: .vertical, area: screen)
        #expect(tree == .split(.vertical, [.split(.horizontal, [.window(1), .window(2)]), .window(3)]))
    }

    @Test("only what the sizes force is read: nesting two deep, two columns of one width, a 2 × 2 grid all give no tree", arguments: [
        [w(1, 842, 1052), w(2, 415, 520), w(3, 415, 520), w(4, 842, 520)],            // a column that holds a row
        [w(1, 560, 700), w(2, 560, 340), w(3, 560, 520), w(4, 560, 520), w(5, 560, 1052)],  // two columns of the same width
        [w(1, 415, 520), w(2, 415, 520), w(3, 415, 520), w(4, 415, 520), w(5, 842, 1052)],  // a grid: two columns or two rows
    ])
    fileprivate func notForced(windows: [T.Window]) {
        #expect(T.reconstruct(windows: windows, root: .horizontal, area: screen) == nil)
    }

    @Test("sizes that do not add up give no tree", arguments: [
        [w(1, 842, 1052), w(2, 842, 300)],            // a column of one short window
        [w(1, 400, 1052), w(2, 400, 1052)],           // widths far short of the screen
        [w(1, 842, 600), w(2, 842, 600), w(3, 842, 1052)],   // rows that overflow their column
    ])
    fileprivate func inconsistent(windows: [T.Window]) {
        #expect(T.reconstruct(windows: windows, root: .horizontal, area: screen) == nil)
    }

    @Test("a single window is the tree, whatever its size says")
    func single() {
        #expect(T.reconstruct(windows: [w(9, 300, 200)], root: .vertical, area: screen) == .window(9))
        #expect(T.reconstruct(windows: [], root: .vertical, area: screen) == nil)
    }
}

@Suite("WorkspaceTree.Axis from AeroSpace's layout name")
struct WorkspaceTreeAxisTests {
    @Test("tiles have an axis; accordions and unknowns have none")
    func axis() {
        #expect(T.Axis(rootLayout: "h_tiles") == .horizontal)
        #expect(T.Axis(rootLayout: "v_tiles") == .vertical)
        #expect(T.Axis(rootLayout: "h_accordion") == nil && T.Axis(rootLayout: "") == nil)
    }
}

@Suite("WorkspaceTree.innerGap")
struct WorkspaceTreeGapTests {
    @Test("a nested container tells the gap: the column spans the tall window, its members add up to less")
    func readFromWorkspace7() {
        let tree = T.reconstruct(windows: ws7, root: .horizontal, area: screen)!
        #expect(T.innerGap(of: tree, windows: ws7) == 12)
    }

    @Test("two windows side by side tell nothing")
    func nothingNested() {
        let two = [w(1, 842, 1052), w(2, 842, 1052)]
        #expect(T.innerGap(of: .split(.horizontal, [.window(1), .window(2)]), windows: two) == nil)
    }
}

@Suite("WorkspaceTree.frames")
struct WorkspaceTreeFramesTests {
    /// A card's box for this screen: 864 × 542 is the screen at scale 0.5.
    private let box = CGRect(x: 0, y: 0, width: 864, height: 542)

    @Test("workspace 7 drawn into a card: every window at its own proportion at the screen's scale, the tiled area centred")
    func workspace7Frames() {
        let tree = T.reconstruct(windows: ws7, root: .horizontal, area: screen)!
        let f = T.frames(of: tree, windows: ws7, screen: screen, in: box, gap: 12)
        #expect(f.count == 5)
        let right = f[8266]!
        #expect(abs(right.width - 421) < 1)                                               // 842 at 0.5
        #expect(abs(right.height - 526) < 1)                                              // 1052 at 0.5
        #expect(abs(right.minX - (8 + 421 + 6)) < 1)                                      // outer 16, column 842, gap 12, all at 0.5
        let (a, b, c, d) = (f[8243]!, f[8240]!, f[3352]!, f[5022]!)
        #expect(abs(a.minY - 8) < 1)                                                      // the outer gap, 16 at 0.5
        #expect(abs(d.maxY - 534) < 1)
        #expect(abs((b.minY - a.maxY) - 6) < 0.5)                                         // 12 at 0.5
        #expect(a.maxY < b.minY && b.maxY < c.minY && c.maxY < d.minY)
        #expect(f.values.allSatisfy { box.insetBy(dx: -0.5, dy: -0.5).contains($0) })
    }

    @Test("a lone window shows the screen's outer gaps around it")
    func single() {
        let lone = [w(1, 1696, 1052)]
        let f = T.frames(of: .window(1), windows: lone, screen: screen, in: box, gap: 12)
        let r = f[1]!
        #expect(abs(r.minX - 8) < 1 && abs(r.minY - 8) < 1)
        #expect(abs(r.width - 848) < 1 && abs(r.height - 526) < 1)
    }

    @Test("a gap the overview knows is used even where this tree could not tell it; unknown, the windows sit edge to edge")
    func gapFromElsewhere() {
        let two = [w(1, 842, 1052), w(2, 842, 1052)]
        let pair = T.Node.split(.horizontal, [.window(1), .window(2)])
        let known = T.frames(of: pair, windows: two, screen: screen, in: box, gap: 12)
        #expect(abs((known[2]!.minX - known[1]!.maxX) - 6) < 0.5)
        let unknown = T.frames(of: pair, windows: two, screen: screen, in: box, gap: nil)
        #expect(unknown[1]!.maxX == unknown[2]!.minX)
    }
}
