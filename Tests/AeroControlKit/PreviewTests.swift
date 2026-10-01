import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// MARK: - Metrics & layout with previews

private func win(_ id: Int, _ app: String, _ title: String = "") -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", title: title)
}

@Suite("layout")
struct LayoutTests {
    @Test("pictures are taken as large as a card can draw one: the lattice cell's inner box, in the screen's pixels, never under the old floor")
    func captureSizeFollowsTheCard() {
        let wide = CGSize(width: 3440, height: 1440)
        let one = AeroControlLayout.captureSize(workspaces: 1, available: wide, backingScale: 1)
        let seven = AeroControlLayout.captureSize(workspaces: 7, available: wide, backingScale: 1)
        let retina = AeroControlLayout.captureSize(workspaces: 7, available: wide, backingScale: 2)
        #expect(one.width > 2000)                                   // one card nearly fills the 3440-point screen
        #expect(seven.width > 720 && seven.width < one.width)       // the old fixed 720 was a blur on this screen
        #expect(abs(retina.width - 2 * seven.width) < 1)            // pixels, not points
        #expect(AeroControlLayout.captureSize(workspaces: 40, available: CGSize(width: 800, height: 500), backingScale: 1)
                == AeroControlLayout.minimumCaptureSize)
    }

    @Test("packed tiles keep the gap the trees draw, scaled to the card, so every card reads as one screen; unknown, the old spacing")
    func tilesShareTheGap() {
        let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084), inner = CGSize(width: 1000, height: 500)
        let scale = AeroControlMetrics.fit(screen.size, into: inner).width / screen.width
        #expect(abs(AeroControlLayout.tileGap(innerGap: 12, screen: screen.size, inner: inner) - 12 * scale) < 0.01)
        #expect(AeroControlLayout.tileGap(innerGap: nil, screen: screen.size, inner: inner) == AeroControlLayout.tileSpacing)
        #expect(AeroControlLayout.tileGap(innerGap: 12, screen: nil, inner: inner) == AeroControlLayout.tileSpacing)
        #expect(AeroControlLayout.tileGap(innerGap: 0, screen: screen.size, inner: inner) == 2)     // never touching
        let packed = AeroControlLayout.packTiles(ratios: [1.5, 1.5], inner: inner, gap: 6, caption: 0)
        let between = packed.tiles[1].x - (packed.tiles[0].x + packed.tiles[0].width)
        #expect(abs(between - 6) < 0.01)
    }

    @Test("a card's tiles are packed inside its inner box at the largest height that fits, each at its window's own shape")
    func packedTiles() {
        let inner = AeroControlLayout.innerSize(of: CGSize(width: 1600, height: 900))
        let windows = (1...4).map { win($0, "Code") }
        let sizes: [Int: CGSize] = [1: CGSize(width: 1600, height: 1000), 2: CGSize(width: 800, height: 1000)]
        let ratios = AeroControlLayout.ratios(of: windows, sizes: sizes, fallback: 1.5)
        #expect(ratios == [1.6, 0.8, 1.5, 1.5])                                  // measured, measured, screen, screen
        let packed = AeroControlLayout.packTiles(ratios: ratios, inner: inner, caption: 0)
        #expect(packed.tiles.count == 4 && packed.width <= inner.width && packed.height <= inner.height)
        #expect(abs(packed.tiles[1].width / packed.tiles[1].height - 0.8) < 0.02)  // the portrait one stays portrait
        // Each card on its own: a card with one window gets a taller picture than one with four.
        let alone = AeroControlLayout.packTiles(ratios: [1.5], inner: inner, caption: 0)
        #expect(alone.tiles[0].height > packed.tiles[0].height)
    }
}

@Suite("the tree drawn into a card")
struct TreeLayoutTests {
    private let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    private let ws7 = [8243, 8240, 3352, 5022, 8266].map { win($0, "Ghostty") }
    private let sizes: [Int: CGSize] = [8243: CGSize(width: 842, height: 257), 8240: CGSize(width: 842, height: 251),
                                        3352: CGSize(width: 842, height: 251), 5022: CGSize(width: 842, height: 257),
                                        8266: CGSize(width: 842, height: 1052)]

    @Test("workspace 7 lands in a screen-shaped box centred in the card, every window inside it, rows read top to bottom")
    func workspace7() throws {
        let inner = CGSize(width: 1000, height: 500)
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7, sizes: sizes, rootLayout: "h_tiles", screen: screen, gap: 12, inner: inner))
        #expect(laid.frames.count == 5)
        let union = laid.frames.values.reduce(CGRect.null) { $0.union($1) }
        #expect(abs(union.width / union.height - 1696 / 1052) < 0.01)                     // the tiled area's own shape
        #expect(abs(union.midX - 500) < 1 && abs(union.midY - 250) < 1)                   // centred
        #expect(union.width <= 1000 && union.height <= 500)
        #expect(laid.rows.first?.contains(8243) == true && laid.rows.first?.contains(8266) == true)
        #expect(laid.rows.last == [5022])
    }

    @Test("a floating window stays out of the tree and lies over it, faint, at its own scale, centred: the one place we cannot know")
    func floatingOverTheTree() throws {
        let inner = CGSize(width: 1000, height: 500)
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isFloating: true)
        var withFloat = sizes; withFloat[99] = CGSize(width: 1200, height: 800)
        let plain = try #require(AeroControlLayout.treeLayout(windows: ws7, sizes: sizes, rootLayout: "h_tiles", screen: screen, gap: nil, inner: inner))
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7 + [float], sizes: withFloat, rootLayout: "h_tiles", screen: screen,
                                                             gap: nil, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
        for id in [8243, 8240, 3352, 5022, 8266] { #expect(laid.frames[id] == plain.frames[id]) }        // the tiling is untouched
        let box = plain.frames.values.reduce(CGRect.null) { $0.union($1) }
        let ghost = try #require(laid.frames[99])
        let scale = AeroControlMetrics.fit(screen.size, into: inner).width / screen.width          // the screen's scale, not the tiling's
        #expect(abs(ghost.width - 1200 * scale) < 1)
        #expect(abs(ghost.height - 800 * scale) < 1)
        #expect(abs(ghost.midX - box.midX) < 1 && abs(ghost.midY - box.midY) < 1)
        #expect(laid.rows.last == [99])
    }

    @Test("a fullscreen window is a ghost over everything, the size of the screen; a float larger than the screen is cut to it")
    func fullscreenAndOversizedGhosts() throws {
        let inner = CGSize(width: 1000, height: 500)
        let full = WindowInfo(windowId: 98, appName: "Zoom", bundleId: "us.zoom", isFullscreen: true)
        let huge = WindowInfo(windowId: 97, appName: "Big", bundleId: "big", isFloating: true)
        var all = sizes; all[98] = screen.size; all[97] = CGSize(width: 3000, height: 3000)
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7 + [full, huge], sizes: all, rootLayout: "h_tiles", screen: screen,
                                                             gap: nil, inner: inner))
        // A fullscreen window covers the whole screen, outer gaps included, so its ghost is the screen's box, larger than the tiling.
        let screenBox = AeroControlMetrics.fit(screen.size, into: inner)
        let full98 = try #require(laid.frames[98])
        #expect(laid.ghosts == [98, 97])
        #expect(abs(full98.width - screenBox.width) < 1)
        #expect(abs(full98.height - screenBox.height) < 1)
        #expect(laid.frames[97] == laid.frames[98])
    }

    @Test("one tiled window under a float is still the tree: the window fills the screen, the float lies over it")
    func loneTiledUnderFloat() throws {
        let tiled = win(1, "Code"), float = WindowInfo(windowId: 2, appName: "Finder", bundleId: "f", isFloating: true)
        let laid = try #require(AeroControlLayout.treeLayout(windows: [tiled, float], sizes: [1: CGSize(width: 1696, height: 1052), 2: CGSize(width: 600, height: 400)],
                                                             rootLayout: "h_accordion", screen: screen, gap: nil, inner: CGSize(width: 1000, height: 500)))
        #expect(laid.frames.count == 2 && laid.ghosts == [2])
    }

    @Test("the overview reads the gap once, from the workspaces that show it, and every card uses it")
    func gapReadOnce() throws {
        let ws7Info = WorkspaceInfo(name: "7", windows: ws7, screenIndex: 1, rootLayout: "h_tiles")
        let pair = [win(1, "Code"), win(2, "Ghostty")]
        let pairInfo = WorkspaceInfo(name: "4", windows: pair, screenIndex: 1, rootLayout: "h_tiles")
        var all = sizes; all[1] = CGSize(width: 842, height: 1052); all[2] = CGSize(width: 842, height: 1052)
        let gap = AeroControlLayout.innerGap(workspaces: [ws7Info, pairInfo], sizes: all, screens: [1: screen])
        #expect(gap == 12)
        #expect(AeroControlLayout.innerGap(workspaces: [pairInfo], sizes: all, screens: [1: screen]) == nil)
        let laid = try #require(AeroControlLayout.treeLayout(windows: pair, sizes: all, rootLayout: "h_tiles", screen: screen,                                                              gap: gap, inner: CGSize(width: 1000, height: 500)))
        let scale = AeroControlMetrics.fit(screen.size, into: CGSize(width: 1000, height: 500)).width / screen.width
        #expect(abs((laid.frames[2]!.minX - laid.frames[1]!.maxX) - 12 * scale) < 0.5)
    }

    /// The owner's workspace 7 as AeroSpace's `%{window-layout-rect}` reports it: screen coordinates, top-left origin,
    /// the visible frame starting under the 33-point menu bar, 16-point outer and 12-point inner gaps.
    private func rected(_ id: Int, _ app: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> WindowInfo {
        WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", layoutRect: CGRect(x: x, y: y, width: w, height: h))
    }
    private var ws7Rected: [WindowInfo] {
        [rected(8243, "Ghostty", 16, 49, 842, 257), rected(8240, "Ghostty", 16, 318, 842, 251), rected(3352, "Ghostty", 16, 581, 842, 251),
         rected(5022, "Ghostty", 16, 844, 842, 257), rected(8266, "Ghostty", 870, 49, 842, 1052)]
    }

    @Test("with AeroSpace's own rects every window is drawn exactly where it is, at the screen's scale: no engine, no guess")
    func rectsDrawExactly() throws {
        let inner = CGSize(width: 1000, height: 500)
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7Rected, sizes: [:], rootLayout: "h_tiles", screen: screen, gap: nil, inner: inner))
        #expect(laid.exact && laid.ghosts.isEmpty && laid.frames.count == 5)
        let fitted = AeroControlMetrics.fit(screen.size, into: inner)
        let scale = fitted.width / screen.width
        let origin = AeroControlLayout.tileOrigin(packed: fitted, inner: inner)
        let right = try #require(laid.frames[8266])
        #expect(abs(right.minX - (origin.x + 870 * scale)) < 0.01 && abs(right.minY - (origin.y + 16 * scale)) < 0.01)
        #expect(abs(right.width - 842 * scale) < 0.01 && abs(right.height - 1052 * scale) < 0.01)
        let third = try #require(laid.frames[3352])
        #expect(abs(third.minY - (origin.y + (581 - 33) * scale)) < 0.01)
        #expect(laid.rows == [[8243, 8266], [8240], [3352], [5022]])
    }

    @Test("a window that refused AeroSpace's size (a minimum width) is drawn where AeroSpace put it, as big as the app made it, over its neighbour as on the screen")
    func minimumSizedWindowOverflowsItsSlot() throws {
        let inner = CGSize(width: 1000, height: 500)
        let row = [rected(287, "Claude", 16, 49, 418, 1052), rected(9134, "Ghostty", 446, 49, 412, 1052)]
        let laid = try #require(AeroControlLayout.treeLayout(windows: row, sizes: [287: CGSize(width: 600, height: 1052)], rootLayout: "h_tiles",
                                                             screen: screen, gap: nil, inner: inner))
        let scale = AeroControlMetrics.fit(screen.size, into: inner).width / screen.width
        let claude = try #require(laid.frames[287]), ghostty = try #require(laid.frames[9134])
        #expect(laid.exact)
        #expect(abs(claude.width - 600 * scale) < 0.01)                       // the app's real width
        #expect(abs(ghostty.minX - claude.minX - 430 * scale) < 0.01)           // the neighbour stays in AeroSpace's slot
        #expect(claude.maxX > ghostty.minX)                                    // so they overlap, as they do on the screen
    }

    @Test("rects that overlap, an accordion's, cannot be a map: only the front one would show, so the card packs tiles instead")
    func overlappingRectsPackTiles() {
        let same = [rected(1, "Claude", 16, 49, 1696, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(AeroControlLayout.treeLayout(windows: same, sizes: [:], rootLayout: "h_accordion", screen: screen, gap: nil,
                                             inner: CGSize(width: 1000, height: 500)) == nil)
        let padded = [rected(1, "Claude", 46, 49, 1636, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(AeroControlLayout.treeLayout(windows: padded, sizes: [:], rootLayout: "h_accordion", screen: screen, gap: nil,
                                             inner: CGSize(width: 1000, height: 500)) == nil)
    }

    @Test("a tiled window without a rect (opened while its workspace was hidden) sends the card back to the engine")
    func missingRectFallsBack() throws {
        var windows = ws7Rected
        windows[2] = WindowInfo(windowId: 3352, appName: "Ghostty", bundleId: "com.Ghostty")
        let laid = try #require(AeroControlLayout.treeLayout(windows: windows, sizes: sizes, rootLayout: "h_tiles", screen: screen, gap: nil,
                                                             inner: CGSize(width: 1000, height: 500)))
        #expect(!laid.exact && laid.frames.count == 5)
    }

    @Test("a float has no rect and stays a ghost over exact rects")
    func ghostOverRects() throws {
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "f", isFloating: true)
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7Rected + [float], sizes: [99: CGSize(width: 600, height: 400)],
                                                             rootLayout: "h_tiles", screen: screen, gap: nil, inner: CGSize(width: 1000, height: 500)))
        #expect(laid.exact && laid.ghosts == [99] && laid.frames.count == 6)
    }

    @Test("no tree without every window's size, without a tiles root, or when the sizes do not add up")
    func noTree() {
        var missing = sizes; missing[3352] = nil
        #expect(AeroControlLayout.treeLayout(windows: ws7, sizes: missing, rootLayout: "h_tiles", screen: screen, gap: nil,
                                             inner: CGSize(width: 1000, height: 500)) == nil)
        #expect(AeroControlLayout.treeLayout(windows: ws7, sizes: sizes, rootLayout: "h_accordion", screen: screen, gap: nil,
                                             inner: CGSize(width: 1000, height: 500)) == nil)
        #expect(AeroControlLayout.treeLayout(windows: ws7, sizes: sizes, rootLayout: "h_tiles", screen: nil, gap: nil,
                                             inner: CGSize(width: 1000, height: 500)) == nil)
    }
}

// MARK: - Store: capture at summon, drop on hide

private let twoWindows = windowsJSON([(1, "1"), (2, "1")])
private let oneWorkspace = workspacesJSON(["1"])

@MainActor private func previewStore(_ bridge: FakeBridge) -> OverviewStore {
    OverviewStore(runner: ScriptRunner(windows: twoWindows, workspaces: oneWorkspace), nativeSystem: bridge)
}
