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
    @Test("pictures are taken first as large as a strip card can be: half the panel high, the screen's shape, in pixels")
    func captureSize() {
        let wide = CGSize(width: 3440, height: 1440)
        let size = AeroControlLayout.captureSize(available: wide, backingScale: 1)
        let half = (1440 * AeroControlLayout.usableScreenFraction * 0.5).rounded(.up)
        #expect(size.height == half && abs(size.width - (half * 3440 / 1440).rounded(.up)) <= 1)
        #expect(abs(AeroControlLayout.captureSize(available: wide, backingScale: 2).width - 2 * size.width) <= 2)
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
        let plain = try #require(AeroControlLayout.treeLayout(windows: ws7Rected, sizes: [:], screen: screen, inner: inner))
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7Rected + [float], sizes: [99: CGSize(width: 1200, height: 800)], screen: screen, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
        for id in [8243, 8240, 3352, 5022, 8266] { #expect(laid.frames[id] == plain.frames[id]) }        // the map is untouched
        let box = plain.frames.values.reduce(CGRect.null) { $0.union($1) }
        let ghost = try #require(laid.frames[99])
        let scale = AeroControlMetrics.fit(screen.size, into: inner).width / screen.width
        #expect(abs(ghost.width - 1200 * scale) < 1)
        #expect(abs(ghost.height - 800 * scale) < 1)
        #expect(abs(ghost.midX - box.midX) < 1 && abs(ghost.midY - box.midY) < 1)
    }

    @Test("a ghost whose size is unknown (no Screen Recording) takes the screen box and leaves the map standing")
    func ghostWithoutSize() throws {
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isFloating: true)
        let inner = CGSize(width: 1000, height: 500)
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7Rected + [float], sizes: [:], screen: screen, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
        let fitted = AeroControlMetrics.fit(screen.size, into: inner)
        #expect(abs(laid.frames[99]!.width - fitted.width) < 0.01 && abs(laid.frames[99]!.height - fitted.height) < 0.01)
    }

    @Test("a fullscreen window is a ghost the size of the screen; a float larger than the screen is cut to it")
    func fullscreenAndOversizedGhosts() throws {
        let inner = CGSize(width: 1000, height: 500)
        let full = WindowInfo(windowId: 98, appName: "Zoom", bundleId: "us.zoom", isFullscreen: true)
        let huge = WindowInfo(windowId: 97, appName: "Big", bundleId: "big", isFloating: true)
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7Rected + [full, huge], sizes: [98: screen.size, 97: CGSize(width: 3000, height: 3000)],
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
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7Rected, sizes: [:], screen: screen, inner: inner))
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

    @Test("a window is where AeroSpace's layout put it, as big as the app made it, hidden or not: AeroSpace sizes hidden windows for their slot too")
    func windowDrawnWhereAerospacePutsIt() throws {
        let inner = CGSize(width: 1000, height: 500)
        let row = [rected(287, "Claude", 16, 49, 418, 1052), rected(9134, "Ghostty", 446, 49, 412, 1052)]
        let scale = AeroControlMetrics.fit(screen.size, into: inner).width / screen.width
        let laid = try #require(AeroControlLayout.treeLayout(windows: row, sizes: [287: CGSize(width: 600, height: 1052)], screen: screen, inner: inner))
        let drawn = try #require(laid.frames[287]), ghostty = try #require(laid.frames[9134])
                #expect(abs(drawn.width - 600 * scale) < 0.01)                                 // a minimum width refused 418
        #expect(abs(ghostty.minX - drawn.minX - 430 * scale) < 0.01)                     // the neighbour stays put
    }

    @Test("rects that overlap, an accordion's, cannot be a map: only the front one would show, so the card packs tiles instead")
    func overlappingRectsPackTiles() {
        let same = [rected(1, "Claude", 16, 49, 1696, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(AeroControlLayout.treeLayout(windows: same, sizes: [:], screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        let padded = [rected(1, "Claude", 46, 49, 1636, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(AeroControlLayout.treeLayout(windows: padded, sizes: [:], screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
    }

    @Test("a tiled window without a rect, or none at all (a release AeroSpace), is no map: the card packs tiles")
    func noRectsNoMap() {
        var windows = ws7Rected
        windows[2] = WindowInfo(windowId: 3352, appName: "Ghostty", bundleId: "com.Ghostty")
        #expect(AeroControlLayout.treeLayout(windows: windows, sizes: sizes, screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        #expect(AeroControlLayout.treeLayout(windows: ws7, sizes: sizes, screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        #expect(AeroControlLayout.treeLayout(windows: ws7Rected, sizes: [:], screen: nil, inner: CGSize(width: 1000, height: 500)) == nil)
    }

    @Test("a float has no rect and stays a ghost over exact rects")
    func ghostOverRects() throws {
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "f", isFloating: true)
        let laid = try #require(AeroControlLayout.treeLayout(windows: ws7Rected + [float], sizes: [99: CGSize(width: 600, height: 400)],
                                                             screen: screen, inner: CGSize(width: 1000, height: 500)))
        #expect(laid.ghosts == [99] && laid.frames.count == 6)
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

    /// The strip is a row of choices, so a card that packs the app's windows packs them in one
    /// row, side by side, even when two rows would give taller pictures: two wide windows on a
    /// card their own shape stacked, and read as one window over another instead of two choices.
    @Test("a packed strip card is one row: wide windows go side by side, not one under the other")
    func packedCardIsOneRow() throws {
        let ws = WorkspaceInfo(name: "1", windows: [WindowInfo(windowId: 1, appName: "Brave", bundleId: "com.Brave"),
                                                    WindowInfo(windowId: 2, appName: "Brave", bundleId: "com.Brave")],
                               screenIndex: 1, rootLayout: "h_accordion")
        let wide = CGSize(width: 2400, height: 1000)
        let l = layout([ws], bundleId: "com.Brave", sizes: [1: wide, 2: wide])
        let card = try #require(l.cards.first)
        let a = try #require(card.frames[1]), b = try #require(card.frames[2])
        #expect(a.maxX <= b.minX && a.minY == b.minY)
        #expect(abs(a.width / a.height - 2.4) < 0.02)
        #expect(a.maxY <= inner(l, card).height + 0.5 && b.maxX <= inner(l, card).width + 0.5)
        // No card mirrors a screen, so the strip is as tall as its row, not as a screen round it.
        #expect((l.height - AeroControlLayout.cardChrome) == a.height && a.minY == 0)
    }

    /// A choice is not bigger for being alone on its workspace: packed cards share the tightest
    /// row's height, and each hugs its row, so one window is not a screen wide round a small picture.
    @Test("packed strip cards share one picture height and hug their windows: a lone window is no bigger than a pair")
    func packedCardsShareHeightAndHug() throws {
        func w(_ id: Int) -> WindowInfo { WindowInfo(windowId: id, appName: "Ghostty", bundleId: "com.Ghostty") }
        let pair = WorkspaceInfo(name: "1", windows: [w(1), w(2)], screenIndex: 1, rootLayout: "h_accordion")
        let lone = WorkspaceInfo(name: "5", windows: [w(3)], screenIndex: 1, rootLayout: "h_accordion")
        let l = layout([pair, lone])
        let heights = Set(l.cards.flatMap { $0.frames.values.map(\.height) })
        #expect(heights.count == 1 && (l.height - AeroControlLayout.cardChrome) == heights.first)
        let alone = try #require(l.cards[1].frames[3])
        #expect(l.cards[1].span.width == alone.width + 2 * AeroControlLayout.cardPadding && alone.minX == 0)
        #expect(l.cards[0].span.width < l.cards[1].span.width * 2.2)                      // two windows and a gap, no screen round them
    }

    @Test("every card is the map's card: its pictures in its screen's shape at one height, as tall as the view allows between a fifth and half the panel, inside the map card's chrome")
    func screenShapedCards() {
        let a = WorkspaceInfo(name: "2", windows: [rected(1, "Ghostty", 16, 49, 842, 1052), rected(2, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let b = WorkspaceInfo(name: "4", windows: [rected(3, "Ghostty", 16, 49, 1696, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let l = layout([a, b])
        let ratio = screen.width / screen.height
        let pad = AeroControlLayout.cardPadding
        #expect((l.height - AeroControlLayout.cardChrome) == AppStripModel.cardHeight(width: 1600 - 4 * pad, gaps: AeroControlLayout.cardGap, sumAspect: 2 * ratio, panelHeight: 1000))
        #expect(l.height == (l.height - AeroControlLayout.cardChrome) + AeroControlLayout.cardChrome)
        // The mirrored card is the screen's shape exactly; the lone window, packed at the full height, within the packer's rounding.
        #expect(l.cards.count == 2 && l.cards.allSatisfy { abs($0.span.width - ((l.height - AeroControlLayout.cardChrome) * ratio).rounded() - 2 * pad) <= 2 })
        #expect(l.cards[1].span.x == l.cards[0].span.width + AeroControlLayout.cardGap)
        #expect(l.width == l.cards[1].span.x + l.cards[1].span.width && l.width <= 1600)
        #expect(CGSize(width: l.cards[0].span.width - 2 * pad, height: l.height - AeroControlLayout.cardChrome) == inner(l, l.cards[0]))
    }

    @Test("a card mirrors its workspace from AeroSpace's rects: the app's windows where they are, the other apps' marked to be drawn faint")
    func mirroredFromRects() throws {
        let ws = WorkspaceInfo(name: "2", windows: [rected(1, "Ghostty", 16, 49, 842, 1052), rected(2, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let card = try #require(layout([ws]).cards.first)
        #expect(card.others == [2] && card.frames.count == 2 && true)
        let left = try #require(card.frames[1]), right = try #require(card.frames[2])
        #expect(left.maxX < right.minX && abs(left.width - right.width) < 0.5)
        let l = layout([ws])
        #expect(card.frames.values.allSatisfy { CGRect(origin: .zero, size: inner(l, card)).insetBy(dx: -0.5, dy: -0.5).contains($0) })
    }

    private func groups(_ n: Int) -> [WorkspaceInfo] {
        (1...n).map { WorkspaceInfo(name: "\($0)", windows: [rected($0, "Ghostty", 16, 49, 1696, 1052)], screenIndex: 1, rootLayout: "h_tiles") }
    }
    private func middle(_ l: AeroControlLayout.StripLayout, _ p: AeroControlLayout.StripPlacement) -> CGFloat { p.x + l.cards[p.card].span.width / 2 }

    @Test("four workspaces in a view that holds fewer: the marked card in the middle, one either side, and the one across cut by both edges")
    func carouselIsWhole() throws {
        let l = layout(groups(4), view: 1200, panel: 1000)
        #expect(l.width > 1200 && l.runsRound(in: 1200))
        let placed = AeroControlLayout.stripPlacements(l, centre: 1, turns: 0, viewWidth: 1200).filter(\.shown)
        let centred = try #require(placed.first { $0.card == 0 })
        #expect(abs(middle(l, centred) - 600) <= 1)                                    // workspace 1 in the middle
        #expect(placed.filter { $0.card == 1 }.count == 1 && placed.filter { $0.card == 3 }.count == 1)
        let across = placed.filter { $0.card == 2 }.map(\.x).sorted()
        #expect(across.count == 2 && across[0] < 0 && across[1] + l.cards[2].span.width > 1200)   // cut on the left and on the right
        #expect(placed.first { $0.card == 1 }!.x > centred.x && placed.first { $0.card == 3 }!.x < centred.x)
    }

    @Test("past the last card the row turns on the same way: every card moves one card along, none jumps back across")
    func carouselTurns() throws {
        let l = layout(groups(4), view: 1200, panel: 1000)
        let onLast = AeroControlLayout.stripPlacements(l, centre: 4, turns: 0, viewWidth: 1200)
        let onFirstAgain = AeroControlLayout.stripPlacements(l, centre: 1, turns: 1, viewWidth: 1200)
        // Nothing comes or goes at the edges as it turns: a card shown after is one drawn before, out of sight if not in it.
        let before = Set(onLast.map(\.identity)), after = Set(onFirstAgain.map(\.identity))
        #expect(Set(onFirstAgain.filter(\.shown).map(\.identity)).isSubset(of: before))
        #expect(Set(onLast.filter(\.shown).map(\.identity)).isSubset(of: after))
        let step = l.cards[0].span.width + AeroControlLayout.cardGap
        for before in onLast {
            guard let after = onFirstAgain.first(where: { $0.card == before.card && $0.copy == before.copy }) else { continue }
            #expect(abs(after.x - (before.x - step)) <= 1)                              // one card to the left, all together
        }
        // Once round, the row looks as it did before it turned.
        let start = AeroControlLayout.stripPlacements(l, centre: 1, turns: 0, viewWidth: 1200).filter(\.shown)
        #expect(Set(start.map { "\($0.card)@\(Int($0.x))" }) == Set(onFirstAgain.filter(\.shown).map { "\($0.card)@\(Int($0.x))" }))
    }

    @Test("three workspaces that would fit run round all the same, the marked card in the middle and each card once; two stand still")
    func carouselFromThree() throws {
        let three = layout(groups(3), view: 20000, panel: 1000)
        #expect(three.width < 20000 && three.runsRound(in: 20000))
        for centre in 1...3 {
            let placed = AeroControlLayout.stripPlacements(three, centre: centre, turns: 0, viewWidth: 20000).filter(\.shown)
            #expect(placed.count == 3)                                                 // a card seen whole is not drawn twice
            #expect(abs(middle(three, try #require(placed.first { $0.card == centre - 1 })) - 10000) <= 1)
        }
        let s1 = AeroControlLayout.stripPlacements(three, centre: 1, turns: 0, viewWidth: 20000).filter(\.shown)
        #expect(s1.first { $0.card == 2 }!.x < s1.first { $0.card == 0 }!.x)           // workspace 3 comes round before 1
        // Two windows in one card: stepping between them moves the marking, not the row.
        let pair = WorkspaceInfo(name: "9", windows: [rected(91, "Ghostty", 16, 49, 842, 1052), rected(92, "Ghostty", 870, 49, 842, 1052)],
                                 screenIndex: 1, rootLayout: "h_tiles")
        let withPair = layout(groups(2) + [pair], view: 20000, panel: 1000)
        #expect(AeroControlLayout.stripPlacements(withPair, centre: 91, turns: 0, viewWidth: 20000)
                == AeroControlLayout.stripPlacements(withPair, centre: 92, turns: 0, viewWidth: 20000))
        let two = layout(groups(2), view: 20000, panel: 1000)
        #expect(!two.runsRound(in: 20000))
        let still = AeroControlLayout.stripPlacements(two, centre: 1, turns: 0, viewWidth: 20000)
        #expect(still == AeroControlLayout.stripPlacements(two, centre: 2, turns: 0, viewWidth: 20000))
        #expect(still.count == 2 && abs((still[0].x + still[1].x + two.cards[1].span.width) / 2 - 10000) <= 1)   // centred as a whole
    }

    @Test("a card whose layout cannot be read lays only the app's windows side by side in it")
    func fallbackSideBySide() throws {
        let ws = WorkspaceInfo(name: "3", windows: [WindowInfo(windowId: 1, appName: "Ghostty", bundleId: "com.Ghostty"),
                                                    WindowInfo(windowId: 2, appName: "Ghostty", bundleId: "com.Ghostty"),
                                                    WindowInfo(windowId: 5, appName: "Code", bundleId: "com.Code")],
                               screenIndex: 1, rootLayout: "h_accordion")
        let l = layout([ws])
        let card = try #require(l.cards.first)
        #expect(Set(card.frames.keys) == [1, 2] && card.others.isEmpty && true)
        let a = try #require(card.frames[1]), b = try #require(card.frames[2])
        #expect(a.maxX <= b.minX)
        #expect([a, b].allSatisfy { CGRect(origin: .zero, size: inner(l, card)).insetBy(dx: -0.5, dy: -0.5).contains($0) })
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

    @Test("closing the overview forgets them with the captures: the next summon takes new ones, and these would never be drawn again")
    func forgottenOnClose() throws {
        let source = image(1100, 690)
        let small = try #require(PictureResampler.picture(source, pixels: CGSize(width: 340, height: 213)))
        previewStore(FakeBridge()).clearPreviews()
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
