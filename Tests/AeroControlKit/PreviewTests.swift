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
    @Test("pictures are taken first as large as a strip card can be: most of the panel high, the screen's shape, in pixels")
    func captureSize() {
        let wide = CGSize(width: 3440, height: 1440)
        let size = AeroControlLayout.captureSize(available: wide, backingScale: 1, workspaces: 5, strip: true)
        let half = (1440 * AeroControlLayout.usableScreenFraction * AppStripModel.tallest).rounded(.up)
        #expect(size.height == half && abs(size.width - (half * 3440 / 1440).rounded(.up)) <= 1)
        #expect(abs(AeroControlLayout.captureSize(available: wide, backingScale: 2, workspaces: 5, strip: true).width - 2 * size.width) <= 2)
    }

    @Test("the map's pictures are taken as large as a card's inner box, the most a tile there draws, never larger than the strip's")
    func mapCaptureSize() {
        let laptop = CGSize(width: 1728, height: 1117)
        let strip = AeroControlLayout.captureSize(available: laptop, backingScale: 2, workspaces: 5, strip: true)
        let map = AeroControlLayout.captureSize(available: laptop, backingScale: 2, workspaces: 5, strip: false)
        let usable = CGSize(width: laptop.width * AeroControlLayout.usableScreenFraction, height: laptop.height * AeroControlLayout.usableScreenFraction)
        let cell = CardGrid.lattice(count: 5, in: usable, cellRatio: AeroControlLayout.screenRatio(for: laptop), gap: AeroControlLayout.cardGap,
                                    chrome: CGSize(width: 2 * AeroControlLayout.cardPadding, height: AeroControlLayout.cardChrome))[0].size
        let inner = AeroControlLayout.inner(of: cell)
        #expect(abs(map.width - 2 * inner.width) <= 2 && abs(map.height - 2 * inner.height) <= 2)
        #expect(map.width * map.height < strip.width * strip.height / 2)                // five cards: under half the pixels
        #expect(AeroControlLayout.captureSize(available: laptop, backingScale: 2, workspaces: 1, strip: false) == strip)   // one card: no larger
    }

    @Test("packed tiles stand one constant apart in the screen's points, scaled to the card, so a packed card reads like one drawn from rects")
    func packedGap() {
        let screen = CGSize(width: 1728, height: 1084), inner = CGSize(width: 1000, height: 500)
        let scale = AeroControlMetrics.fit(screen, into: inner).width / screen.width
        #expect(abs(AeroControlLayout.packedGap(screen: screen, inner: inner) - AeroControlLayout.packedGapOnScreen * scale) < 0.01)
        #expect(AeroControlLayout.packedGap(screen: nil, inner: inner) == AeroControlLayout.tileSpacing)
        #expect(AeroControlLayout.packedGap(screen: screen, inner: CGSize(width: 10, height: 5)) == 2)   // never touching
    }

    @Test("stacking: a ghost lies over everything, the focused window over its neighbours, the rest as listed")
    func stacking() {
        #expect(AeroControlLayout.stacking(windowId: 9, focused: 9, ghosts: []) == 1)
        #expect(AeroControlLayout.stacking(windowId: 4, focused: 9, ghosts: []) == 0)
        #expect(AeroControlLayout.stacking(windowId: 4, focused: 9, ghosts: [4]) == 2)
        #expect(AeroControlLayout.stacking(windowId: 9, focused: 9, ghosts: [9]) == 2)
    }

    /// What the card does: the largest shared picture height that fits, then the rows at it.
    private func pack(_ ratios: [CGFloat], _ inner: CGSize) -> TilePacker.Packed {
        let height = TilePacker.packHeight(ratios: ratios, width: inner.width, height: inner.height, gap: AeroControlLayout.tileSpacing, caption: 0)
        return TilePacker.packRows(ratios: ratios, tileHeight: max(1, height), width: inner.width, gap: AeroControlLayout.tileSpacing, caption: 0)
    }

    @Test("a card's tiles are packed inside its inner box at the largest height that fits, each at its window's own shape")
    func packedTiles() {
        let inner = CGSize(width: 1600 - 2 * AeroControlLayout.cardPadding, height: 900 - AeroControlLayout.cardChrome)
        let windows = (1...4).map { win($0, "Code") }
        let sizes: [Int: CGSize] = [1: CGSize(width: 1600, height: 1000), 2: CGSize(width: 800, height: 1000)]
        let ratios = AeroControlLayout.ratios(of: windows, sizes: sizes, fallback: 1.5)
        #expect(ratios == [1.6, 0.8, 1.5, 1.5])                                  // measured, measured, screen, screen
        let packed = pack(ratios, inner)
        #expect(packed.tiles.count == 4 && packed.width <= inner.width && packed.height <= inner.height)
        #expect(abs(packed.tiles[1].width / packed.tiles[1].height - 0.8) < 0.02)  // the portrait one stays portrait
        // Each card on its own: a card with one window gets a taller picture than one with four.
        let alone = pack([1.5], inner)
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
    /// The owner's workspace 7 as AeroSpace's `%{window-layout-rect}` reports it: screen coordinates, top-left origin,
    /// the visible frame starting under the 33-point menu bar, 16-point outer and 12-point inner gaps.
    private var ws7Rected: [WindowInfo] {
        [rected(8243, "Ghostty", 16, 49, 842, 257), rected(8240, "Ghostty", 16, 318, 842, 251), rected(3352, "Ghostty", 16, 581, 842, 251),
         rected(5022, "Ghostty", 16, 844, 842, 257), rected(8266, "Ghostty", 870, 49, 842, 1052)]
    }

    @Test("a floating window is not in the map and lies over it, faint, at its own scale, centred: the one place AeroSpace does not say")
    func floatingOverTheMap() throws {
        let inner = CGSize(width: 1000, height: 500)
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isFloating: true)
        let plain = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected), sizes: [:], screen: screen, inner: inner))
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected + [float]), sizes: [99: CGSize(width: 1200, height: 800)], screen: screen, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
        for id in [8243, 8240, 3352, 5022, 8266] { #expect(laid.frames[id] == plain.frames[id]) }        // the map is untouched
        let box = plain.frames.values.reduce(CGRect.null) { $0.union($1) }
        let ghost = try #require(laid.frames[99])
        let scale = AeroControlMetrics.fit(screen.size, into: inner).width / screen.width
        #expect(abs(ghost.width - 1200 * scale) < 1)
        #expect(abs(ghost.height - 800 * scale) < 1)
        #expect(abs(ghost.midX - box.midX) < 1 && abs(ghost.midY - box.midY) < 1)
    }

    @Test("a minimized window, or one of a hidden app, is out of the layout and has no rect: it lies over the map rather than unseat it")
    func hiddenOverTheMap() throws {
        let minimized = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isHidden: true)
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected + [minimized]), sizes: [:], screen: screen, inner: CGSize(width: 1000, height: 500)))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
    }

    @Test("a ghost whose size is unknown (no Screen Recording) takes the screen box and leaves the map standing")
    func ghostWithoutSize() throws {
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isFloating: true)
        let inner = CGSize(width: 1000, height: 500)
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected + [float]), sizes: [:], screen: screen, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
        let fitted = AeroControlMetrics.fit(screen.size, into: inner)
        #expect(abs(laid.frames[99]!.width - fitted.width) < 0.01 && abs(laid.frames[99]!.height - fitted.height) < 0.01)
    }

    @Test("a fullscreen window is a ghost the size of the screen; a float larger than the screen is cut to it")
    func fullscreenAndOversizedGhosts() throws {
        let inner = CGSize(width: 1000, height: 500)
        let full = WindowInfo(windowId: 98, appName: "Zoom", bundleId: "us.zoom", isFullscreen: true)
        let huge = WindowInfo(windowId: 97, appName: "Big", bundleId: "big", isFloating: true)
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected + [full, huge]), sizes: [98: screen.size, 97: CGSize(width: 3000, height: 3000)],
                                                             screen: screen, inner: inner))
        let screenBox = AeroControlMetrics.fit(screen.size, into: inner)
        let full98 = try #require(laid.frames[98])
        #expect(laid.ghosts == [98, 97])
        #expect(abs(full98.width - screenBox.width) < 1)
        #expect(abs(full98.height - screenBox.height) < 1)
        #expect(laid.frames[97] == laid.frames[98])
    }

    @Test("with AeroSpace's own rects every window is drawn exactly where it is, at the screen's scale: no engine, no guess")
    func rectsDrawExactly() throws {
        let inner = CGSize(width: 1000, height: 500)
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected), sizes: [:], screen: screen, inner: inner))
        #expect(laid.ghosts.isEmpty && laid.frames.count == 5)
        let fitted = AeroControlMetrics.fit(screen.size, into: inner)
        let scale = fitted.width / screen.width
        let origin = AeroControlLayout.tileOrigin(packed: fitted, inner: inner)
        let right = try #require(laid.frames[8266])
        #expect(abs(right.minX - (origin.x + 870 * scale)) < 0.01 && abs(right.minY - (origin.y + 16 * scale)) < 0.01)
        #expect(abs(right.width - 842 * scale) < 0.01 && abs(right.height - 1052 * scale) < 0.01)
        let third = try #require(laid.frames[3352])
        #expect(abs(third.minY - (origin.y + (581 - 33) * scale)) < 0.01)
    }

    @Test("a window is drawn at its slot, whatever size its app made it: AeroSpace's layout is the truth, an app's refusal of it is not")
    func windowDrawnAtItsSlot() throws {
        let inner = CGSize(width: 1000, height: 500)
        let row = [rected(287, "Claude", 16, 49, 418, 1052), rected(9134, "Ghostty", 446, 49, 412, 1052)]
        let scale = AeroControlMetrics.fit(screen.size, into: inner).width / screen.width
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: row), sizes: [287: CGSize(width: 600, height: 1052)], screen: screen, inner: inner))
        let drawn = try #require(laid.frames[287]), ghostty = try #require(laid.frames[9134])
        #expect(abs(drawn.width - 418 * scale) < 0.01)                                   // the slot, not the 600 the app refused it for
        #expect(abs(ghostty.minX - drawn.minX - 430 * scale) < 0.01)
    }

    @Test("rects that overlap, an accordion's, cannot be a map: only the front one would show, so the card packs tiles instead")
    func overlappingRectsPackTiles() {
        let same = [rected(1, "Claude", 16, 49, 1696, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: same), sizes: [:], screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        let padded = [rected(1, "Claude", 46, 49, 1636, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: padded), sizes: [:], screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
    }

    @Test("a picture is of the window as it is, and stale when the window's own shape no longer fits it; its slot stands in only for a window never measured, and a window with neither is not")
    func stalePictures() {
        let tiled = WorkspaceInfo(name: "1", windows: [rected(1, "A", 0, 0, 800, 600), rected(2, "A", 0, 0, 800, 600), rected(5, "A", 0, 0, 800, 600), rected(6, "A", 0, 0, 800, 600)])
        let floats = WorkspaceInfo(name: "2", windows: [win(3, "A"), win(4, "A")])
        let pictures = [1: CGSize(width: 400, height: 300), 2: CGSize(width: 400, height: 100), 3: CGSize(width: 400, height: 100), 4: CGSize(width: 400, height: 100), 5: CGSize(width: 400, height: 150), 6: CGSize(width: 400, height: 100)]
        let sizes = [1: CGSize(width: 800, height: 600), 2: CGSize(width: 800, height: 600), 3: CGSize(width: 800, height: 200), 5: CGSize(width: 1600, height: 600)]
        #expect(AeroControlLayout.stale(workspaces: [tiled, floats], pictures: pictures, sizes: sizes) == [2, 6])   // 5 refused its slot and its picture fits it as it is; 6 was never measured, so its slot says
    }

    @Test("a tiled window without a rect, or none at all (a release AeroSpace), is no map: the card packs tiles")
    func noRectsNoMap() {
        var windows = ws7Rected
        windows[2] = WindowInfo(windowId: 3352, appName: "Ghostty", bundleId: "com.Ghostty")
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: windows), sizes: sizes, screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7), sizes: sizes, screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected), sizes: [:], screen: nil, inner: CGSize(width: 1000, height: 500)) == nil)
    }

}

@Suite("the map as drawn")
struct MapLayoutTests {
    private let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    private func layout(_ workspaces: [WorkspaceInfo], filtering: Bool = false) -> [AeroControlLayout.MapCard] {
        AeroControlLayout.mapLayout(workspaces: workspaces, sizes: [:], screens: [1: screen], available: CGSize(width: 1800, height: 1100),
                                    usable: CGSize(width: 1600, height: 900), filtering: filtering)
    }

    @Test("every card where the lattice put it, its windows where the card draws them, both in the map's space; an empty workspace's card holds one stand-in, keyed -1 - its index, the size of its inner box")
    func cardsAsDrawn() throws {
        let a = WorkspaceInfo(name: "1", windows: [rected(1, "A", 16, 49, 842, 1052), rected(2, "B", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let cards = layout([a, WorkspaceInfo(name: "2", windows: [], screenIndex: 1)])
        #expect(cards.map(\.workspace) == ["1", "2"] && cards[0].frame.minX < cards[1].frame.minX && cards[0].frame.size == cards[1].frame.size)
        let left = try #require(cards[0].grid.windows[1]), right = try #require(cards[0].grid.windows[2])
        #expect(cards[0].frame.contains(left) && cards[0].frame.contains(right) && left.maxX <= right.minX && left.minY > cards[0].frame.minY + AeroControlLayout.badgeLane)
        let inCard = try #require(cards[0].frames[1])                                          // the card draws from its inner box
        #expect(abs(inCard.minX - (left.minX - cards[0].frame.minX - AeroControlLayout.cardPadding)) < 0.01
                && abs(inCard.minY - (left.minY - cards[0].frame.minY - AeroControlLayout.badgeLane - AeroControlLayout.tileSpacing)) < 0.01)
        let standIn = try #require(cards[1].grid.windows[-2])
        #expect(cards[1].grid.windows.count == 1 && standIn.size == AeroControlLayout.inner(of: cards[1].frame.size) && cards[1].frame.contains(standIn))
    }

    @Test("a filtered map draws only the workspaces given, each packing what it holds, and a float lies over the layout as a ghost")
    func filteredAndGhosts() throws {
        let float = WindowInfo(windowId: 9, appName: "C", bundleId: "com.C", isFloating: true)
        let a = WorkspaceInfo(name: "1", windows: [rected(1, "A", 16, 49, 842, 1052), rected(2, "B", 870, 49, 842, 1052), float], screenIndex: 1, rootLayout: "h_tiles")
        #expect(layout([a]).first?.ghosts == [9])
        let packed = try #require(layout([a], filtering: true).first)
        #expect(packed.ghosts.isEmpty && packed.frames.count == 3)
    }
}

@Suite("the strip's cards")
struct StripLayoutTests {
    private let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    /// The box a card's pictures fill, which its frames are in.
    private func inner(_ l: AeroControlLayout.StripLayout, _ card: AeroControlLayout.StripCard) -> CGSize {
        CGSize(width: card.span.width - 2 * AeroControlLayout.cardPadding, height: (l.height - AeroControlLayout.cardChrome))
    }
    private func layout(_ groups: [WorkspaceInfo], bundleId: String = "com.Ghostty", sizes: [Int: CGSize] = [:],
                        view: CGFloat = 1600, panel: CGFloat = 1000) -> AeroControlLayout.StripLayout {
        AeroControlLayout.stripLayout(groups: groups, bundleId: bundleId, sizes: sizes, screens: [1: screen], fallbackScreen: screen,
                                      viewWidth: view, panelHeight: panel)
    }

    @Test("a card that cannot be read is its workspace's screen all the same: the app's windows only, packed in it as the map packs them, as large as it allows")
    func packedCardIsTheScreen() throws {
        let l = layout([ghostty("3", 1...4, [WindowInfo(windowId: 9, appName: "Code", bundleId: "com.Code")]), ghostty("4", 5...5)])   // four and a Code, one alone
        let four = try #require(l.cards.first), box = inner(l, four)
        #expect(four.frames.count == 4 && four.others.isEmpty && l.cards[1].frames.count == 1)
        #expect(Set(four.frames.values.map(\.minY)).count == 2 && four.frames.values.allSatisfy { $0.maxX <= box.width + 0.5 && $0.maxY <= box.height + 0.5 })   // two by two
        #expect(l.cards[0].span.width == l.cards[1].span.width && (l.cards[1].frames[5]?.width ?? 0) > box.width * 0.9)   // each a screen, one window filling it
        let wide = CGSize(width: 2400, height: 1000), two = try #require(layout([ghostty("3", 1...2)], sizes: [1: wide, 2: wide]).cards.first)
        #expect(two.frames[1]?.minY == two.frames[2]?.minY)                               // two are side by side, even where stacked would be larger
    }
    private func ghostty(_ ws: String, _ ids: ClosedRange<Int>, _ other: [WindowInfo] = []) -> WorkspaceInfo {
        WorkspaceInfo(name: ws, windows: ids.map { WindowInfo(windowId: $0, appName: "Ghostty", bundleId: "com.Ghostty") } + other, screenIndex: 1, rootLayout: "h_accordion")
    }

    @Test("every card is the map's card: its pictures in its screen's shape at one height, up to a third of the panel, inside the map card's chrome")
    func screenShapedCards() {
        let a = WorkspaceInfo(name: "2", windows: [rected(1, "Ghostty", 16, 49, 842, 1052), rected(2, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let b = WorkspaceInfo(name: "4", windows: [rected(3, "Ghostty", 16, 49, 1696, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let l = layout([a, b])
        let ratio = screen.width / screen.height, pad = AeroControlLayout.cardPadding
        #expect((l.height - AeroControlLayout.cardChrome) == AppStripModel.cardHeight(view: 1600, cards: 2, aspect: ratio, chrome: 2 * pad + AeroControlLayout.cardGap, panelHeight: 1000))
        // The mirrored card is the screen's shape exactly; the lone window, packed at the full height, within the packer's rounding.
        #expect(l.cards.count == 2 && l.cards.allSatisfy { abs($0.span.width - ((l.height - AeroControlLayout.cardChrome) * ratio).rounded() - 2 * pad) <= 2 })
        #expect(l.cards[1].span.x == l.cards[0].span.width + AeroControlLayout.cardGap && l.width == l.cards[1].span.x + l.cards[1].span.width && !l.slides(in: 1600))
        #expect(CGSize(width: l.cards[0].span.width - 2 * pad, height: l.height - AeroControlLayout.cardChrome) == inner(l, l.cards[0]))
    }

    @Test("a card mirrors its workspace from AeroSpace's rects: the app's windows where they are, the other apps' marked to be drawn faint")
    func mirroredFromRects() throws {
        let ws = WorkspaceInfo(name: "2", windows: [rected(1, "Ghostty", 16, 49, 842, 1052), rected(2, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let l = layout([ws]), card = try #require(l.cards.first)
        let left = try #require(card.frames[1]), right = try #require(card.frames[2])
        #expect(card.others == [2] && card.frames.count == 2 && left.maxX < right.minX && abs(left.width - right.width) < 0.5)
        #expect(card.frames.values.allSatisfy { CGRect(origin: .zero, size: inner(l, card)).insetBy(dx: -0.5, dy: -0.5).contains($0) })
    }

    private func groups(_ n: Int) -> [WorkspaceInfo] {
        // Mirrored cards, two windows each: packed cards share the view and never turn.
        (1...n).map { WorkspaceInfo(name: "\($0)", windows: [rected($0, "Ghostty", 16, 49, 842, 1052), rected($0 + 100, "Ghostty", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles") }
    }

    @Test("the cards for the keys: each card's span on the unrolled row, and in it the app's own windows where they are drawn; the other apps' are not stops")
    func gridForTheKeys() throws {
        let ws = WorkspaceInfo(name: "2", windows: [rected(1, "Ghostty", 16, 49, 842, 1052), rected(2, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let l = layout(groups(2) + [ws]), grid = l.grid, card = try #require(grid.last), laid = try #require(l.cards.last)
        #expect(grid.count == 3 && card.frame == CGRect(x: laid.span.x, y: 0, width: laid.span.width, height: l.height))
        #expect(card.windows.keys.sorted() == [1] && card.windows[1] == laid.frames[1]?.offsetBy(dx: laid.span.x + AeroControlLayout.cardPadding, dy: 0))
    }

    @Test("workspaces that do not fit slide: the marked one whole in the middle, the next cut by the edge, up to the row's ends")
    func slidingRow() throws {
        let l = layout(groups(5), view: 1600, panel: 1000), w = l.cards[0].span.width
        func at(_ centre: Int) -> [CGFloat] { AeroControlLayout.stripPlacements(l, centre: centre, viewWidth: 1600).map(\.x) }
        #expect(l.slides(in: 1600) && at(1)[0] == 0 && at(1).contains { $0 < 1600 && $0 + w > 1600 })   // the first at the left edge, the row cut on the right
        #expect(abs(at(3)[2] + w / 2 - 800) <= 1 && at(3).contains { $0 < 0 && $0 + w > 0 })              // in the middle, cut on both sides
        #expect(abs(at(5)[4] + w - 1600) <= 1)                                                            // the last at the right edge
    }

    @Test("a row that fits stands still and centred, and stepping between a card's windows moves only the marking")
    func stillWhenItFits() throws {
        let pair = WorkspaceInfo(name: "9", windows: [rected(91, "Ghostty", 16, 49, 842, 1052), rected(92, "Ghostty", 870, 49, 842, 1052)],
                                 screenIndex: 1, rootLayout: "h_tiles")
        let row = layout([pair], view: 1600, panel: 1000), still = AeroControlLayout.stripPlacements(row, centre: 91, viewWidth: 1600)
        #expect(!row.slides(in: 1600) && still == AeroControlLayout.stripPlacements(row, centre: 92, viewWidth: 1600))
        #expect(still.count == 1 && abs(still[0].x + row.cards[0].span.width / 2 - 800) <= 1)
    }
}

// MARK: - Store: capture at summon, drop on hide

/// A window with AeroSpace's layout rect, as the owner's branch reports one.
private func rected(_ id: Int, _ app: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", layoutRect: CGRect(x: x, y: y, width: w, height: h))
}

private let twoWindows = windowsJSON([(1, "1"), (2, "1")])
private let oneWorkspace = workspacesJSON(["1"])

@MainActor private func previewStore(_ bridge: FakeBridge) -> OverviewStore {
    OverviewStore(runner: ScriptRunner(windows: twoWindows, workspaces: oneWorkspace), nativeSystem: bridge)
}

@Suite("a picture at the screen's pixels")
@MainActor struct PictureResamplerTests {
    private func image(_ w: Int, _ h: Int) -> CGImage {
        let context = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()!
    }

    @Test("a capture is scaled to exactly the pixels it is drawn in, once, and kept for that size")
    func exactPixels() throws {
        let source = image(1100, 690)
        let small = try #require(PictureResampler.picture(source, pixels: CGSize(width: 340, height: 213)))
        #expect(small.width == 340 && small.height == 213)
        #expect(PictureResampler.picture(source, pixels: CGSize(width: 340, height: 213)) === small)   // cached
        #expect(PictureResampler.picture(source, pixels: CGSize(width: 1100, height: 690)) === source) // already that size
        #expect(PictureResampler.picture(source, pixels: .zero) == nil)
    }

    @Test("a picture taken again takes its scaled copies with it: they are not kept, nor handed to a new picture at its address")
    func forgottenWhenReplaced() throws {
        let source = image(1100, 690), other = image(1100, 690)
        let small = try #require(PictureResampler.picture(source, pixels: CGSize(width: 340, height: 213)))
        let kept = try #require(PictureResampler.picture(other, pixels: CGSize(width: 340, height: 213)))
        PictureResampler.forget(NSImage(cgImage: source, size: .zero))
        #expect(PictureResampler.picture(source, pixels: CGSize(width: 340, height: 213)) !== small)
        #expect(PictureResampler.picture(other, pixels: CGSize(width: 340, height: 213)) === kept)       // only its own
    }

    @Test("closing the overview forgets them with the captures: the next summon takes new ones, and these would never be drawn again")
    func forgottenOnClose() throws {
        let source = image(1100, 690)
        let small = try #require(PictureResampler.picture(source, pixels: CGSize(width: 340, height: 213)))
        previewStore(FakeBridge()).endVisit()
        #expect(PictureResampler.picture(source, pixels: CGSize(width: 340, height: 213)) !== small)
    }
}

@Suite("an app's icon")
@MainActor struct AppIconTests {
    @Test("an icon is held as one large picture, the same each time it is asked for, so its exact-size copy can be kept")
    func iconIsOneStablePicture() throws {
        let icon = NativeApiBridgeAdapter.largeRepresentation(of: NSWorkspace.shared.icon(for: .applicationBundle))
        let first = try #require(icon.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(first.width >= 256 && first.width == first.height)          // 256 points: 512 pixels on a 2x screen
        #expect(icon.cgImage(forProposedRect: nil, context: nil, hints: nil) === first)
    }
}
