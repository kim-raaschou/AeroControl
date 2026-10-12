import AppKit
import Testing
@testable import AeroControl
@testable import Common

// MARK: - Metrics & layout with previews

private func win(_ id: Int, _ app: String, _ title: String = "") -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", title: title)
}

@Suite("layout")
struct LayoutTests {
    @Test("packed tiles stand one constant apart in the screen's points, scaled to the card, so a packed card reads like one drawn from rects")
    func packedGap() {
        let screen = CGSize(width: 1728, height: 1084), inner = CGSize(width: 1000, height: 500)
        let scale = AeroControlMetrics.fit(screen, into: inner).width / screen.width
        #expect(abs(AeroControlLayout.packedGap(screen: screen, inner: inner) - AeroControlLayout.packedGapOnScreen * scale) < 0.01)
        #expect(AeroControlLayout.packedGap(screen: nil, inner: inner) == AeroControlLayout.tileSpacing)
        #expect(AeroControlLayout.packedGap(screen: screen, inner: CGSize(width: 10, height: 5)) == 2)   // never touching
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

    @Test("a floating window lies over the map where it stands on the screen, at the screen's scale, faint: AeroSpace leaves floats to the window server, which says where")
    func floatingOverTheMap() throws {
        let inner = CGSize(width: 1000, height: 500)
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isFloating: true)
        let plain = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected), frames: [:], screen: screen, inner: inner))
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected + [float]), frames: [99: CGRect(x: 216, y: 233, width: 1200, height: 800)], screen: screen, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
        for id in [8243, 8240, 3352, 5022, 8266] { #expect(laid.frames[id] == plain.frames[id]) }
        let fitted = AeroControlMetrics.fit(screen.size, into: inner), scale = fitted.width / screen.width
        let origin = AeroControlLayout.tileOrigin(packed: fitted, inner: inner), ghost = try #require(laid.frames[99])
        #expect(abs(ghost.minX - (origin.x + 216 * scale)) < 0.01 && abs(ghost.minY - (origin.y + 200 * scale)) < 0.01)
        #expect(abs(ghost.width - 1200 * scale) < 0.01 && abs(ghost.height - 800 * scale) < 0.01)
    }

    @Test("a minimized window, or one of a hidden app, is out of the layout and has no rect: it lies over the map rather than unseat it")
    func hiddenOverTheMap() throws {
        let minimized = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isHidden: true)
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected + [minimized]), frames: [:], screen: screen, inner: CGSize(width: 1000, height: 500)))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
    }

    @Test("a ghost whose size is unknown (no Screen Recording) takes the screen box and leaves the map standing")
    func ghostWithoutSize() throws {
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isFloating: true)
        let inner = CGSize(width: 1000, height: 500)
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected + [float]), frames: [:], screen: screen, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
        let fitted = AeroControlMetrics.fit(screen.size, into: inner)
        #expect(abs(laid.frames[99]!.width - fitted.width) < 0.01 && abs(laid.frames[99]!.height - fitted.height) < 0.01)
    }

    @Test("a fullscreen window is a ghost the size of the screen; a float larger than the screen is cut to it")
    func fullscreenAndOversizedGhosts() throws {
        let inner = CGSize(width: 1000, height: 500)
        let full = WindowInfo(windowId: 98, appName: "Zoom", bundleId: "us.zoom", isFullscreen: true)
        let huge = WindowInfo(windowId: 97, appName: "Big", bundleId: "big", isFloating: true)
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected + [full, huge]), frames: [98: screen, 97: CGRect(x: 0, y: 33, width: 3000, height: 3000)],
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
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected), frames: [:], screen: screen, inner: inner))
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
        let laid = try #require(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: row), frames: framed([287: CGSize(width: 600, height: 1052)]), screen: screen, inner: inner))
        let drawn = try #require(laid.frames[287]), ghostty = try #require(laid.frames[9134])
        #expect(abs(drawn.width - 418 * scale) < 0.01)                                   // the slot, not the 600 the app refused it for
        #expect(abs(ghostty.minX - drawn.minX - 430 * scale) < 0.01)
    }

    @Test("a window alone on its workspace is drawn in the slot AeroSpace gives it, though the window itself has not been resized to it yet")
    func aloneInItsSlot() throws {
        let alone = WorkspaceInfo(name: "9", windows: [rected(1, "GitHub", 16, 49, 1696, 1052)])
        let laid = try #require(AeroControlLayout.treeLayout(alone, frames: [1: CGRect(x: 0, y: 0, width: 842, height: 1052)], screen: screen, inner: CGSize(width: 1000, height: 600)))
        let fitted = AeroControlMetrics.fit(screen.size, into: CGSize(width: 1000, height: 600))
        #expect(abs(laid.frames[1]!.width - fitted.width * 1696 / screen.width) < 1)
    }

    @Test("rects that overlap, an accordion's, cannot be a map: only the front one would show, so the card packs tiles instead")
    func overlappingRectsPackTiles() {
        let same = [rected(1, "Claude", 16, 49, 1696, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: same), frames: [:], screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        let padded = [rected(1, "Claude", 46, 49, 1636, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: padded), frames: [:], screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
    }

    @Test("a tiled window without a rect, or none at all (a release AeroSpace), is no map: the card packs tiles")
    func noRectsNoMap() {
        var windows = ws7Rected
        windows[2] = WindowInfo(windowId: 3352, appName: "Ghostty", bundleId: "com.Ghostty")
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: windows), frames: framed(sizes), screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7), frames: framed(sizes), screen: screen, inner: CGSize(width: 1000, height: 500)) == nil)
        #expect(AeroControlLayout.treeLayout(WorkspaceInfo(name: "7", windows: ws7Rected), frames: [:], screen: nil, inner: CGSize(width: 1000, height: 500)) == nil)
    }

}

@Suite("the map as drawn")
struct MapLayoutTests {
    private let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    private func layout(_ workspaces: [WorkspaceInfo], filtering: Bool = false) -> [AeroControlLayout.LaidCard] {
        AeroControlLayout.mapLayout(workspaces: workspaces, frames: [:], screens: [1: screen], available: CGSize(width: 1800, height: 1100), filtering: filtering)
    }

    @Test("every card where the lattice put it, its windows where the card draws them, both in the map's space; an empty workspace's card holds one stand-in, keyed by its name, the size of its inner box")
    func cardsAsDrawn() throws {
        let a = WorkspaceInfo(name: "1", windows: [rected(1, "A", 16, 49, 842, 1052), rected(2, "B", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let cards = layout([a, WorkspaceInfo(name: "2", windows: [], screenIndex: 1)])
        #expect(cards.map(\.workspace) == ["1", "2"] && cards[0].frame.minX < cards[1].frame.minX && cards[0].frame.size == cards[1].frame.size)
        let left = try #require(cards[0].grid.windows[1]), right = try #require(cards[0].grid.windows[2])
        #expect(cards[0].frame.contains(left) && cards[0].frame.contains(right) && left.maxX <= right.minX && left.minY > cards[0].frame.minY + AeroControlLayout.badgeLane)
        let inCard = try #require(cards[0].frames[1])                                          // the card draws from its inner box
        #expect(abs(inCard.minX - (left.minX - cards[0].frame.minX - AeroControlLayout.cardPadding)) < 0.01
                && abs(inCard.minY - (left.minY - cards[0].frame.minY - AeroControlLayout.badgeLane - AeroControlLayout.tileSpacing)) < 0.01)
        let standIn = try #require(cards[1].grid.windows[WorkspaceInfo(name: "2", windows: []).standIn])
        let ids = (1...10).map { WorkspaceInfo(name: "\($0)", windows: []).standIn }
        #expect(Set(ids).count == 10 && ids.allSatisfy { $0 < 0 } && ids == (1...10).map { WorkspaceInfo(name: "\($0)", windows: []).standIn })
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
    private typealias L = AeroControlLayout
    private let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084)
    /// The box a card's pictures fill, which its frames are in.
    private func inner(_ card: L.LaidCard) -> CGSize {
        CGSize(width: card.frame.width - 2 * L.cardPadding, height: card.frame.height - L.cardChrome)
    }
    private let available = CGSize(width: 1702, height: 1124)
    private var view: CGSize { L.usable(available) }
    private func layout(_ groups: [WorkspaceInfo], bundleId: String = "com.Ghostty", frames: [Int: CGRect] = [:]) -> [L.LaidCard] {
        L.stripLayout(groups: groups, bundleId: bundleId, frames: frames, screens: [1: screen], available: available)
    }

    @Test("a card is at most 45% of the panel high, one or many; more each take a 3.5th of the view's width")
    func cardHeight() {
        func h(_ cards: Int, _ view: CGFloat = 1900) -> CGFloat { L.stripCardHeight(view: view, cards: cards, aspect: 1.6, chrome: 24, panelHeight: 1085) }
        #expect(L.tallest == 0.45 && h(1) == (1085 * 0.45).rounded() && h(2) == h(1) && h(5) == ((1900 / L.seen - 24) / 1.6).rounded(.down))
        #expect(h(5, 900) == ((900 / L.seen - 24) / 1.6).rounded(.down) && h(3, 900) == ((900 / 3 - 24) / 1.6).rounded(.down))
    }

    @Test("a card holds the app's windows on its workspace and no other app's, packed inside it; one window alone fills its height")
    func cardHoldsTheAppsWindows() throws {
        let stack = ghostty("3", 1...4, [WindowInfo(windowId: 9, appName: "Code", bundleId: "com.Code")])
        let l = layout([stack, ghostty("4", 5...5)])
        let four = try #require(l.first), box = CGRect(origin: .zero, size: inner(four)).insetBy(dx: -0.5, dy: -0.5)
        #expect(four.frames.keys.sorted() == [1, 2, 3, 4] && four.frames.values.allSatisfy { box.contains($0) })
        #expect((l[1].frames[5]?.height ?? 0) > inner(l[1]).height * 0.9)
    }

    @Test("packed tiles take the shape of AeroSpace's slot, not the window's size, which lags while an app resizes: an accordion's windows are alike")
    func packedFromTheSlot() throws {
        let slot = CGRect(x: 16, y: 49, width: 1696, height: 1052)
        let accordion = WorkspaceInfo(name: "2", windows: (1...3).map { WindowInfo(windowId: $0, appName: "Ghostty", bundleId: "com.Ghostty", layoutRect: slot) }, screenIndex: 1, rootLayout: "h_accordion")
        let card = try #require(layout([accordion], frames: [1: CGRect(x: 0, y: 0, width: 280, height: 1052)]).first)
        #expect(Set(card.frames.values.map { ($0.width / $0.height * 100).rounded() }).count == 1)
    }

    @Test("a card takes the width the row gives it, not its screen's shape: two windows side by side are each nearly the card's height")
    func cardTakesTheRow() throws {
        let screenSized = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        let card = try #require(layout([ghostty("3", 1...2)], frames: [1: screenSized, 2: screenSized]).first)
        let one = try #require(card.frames[1])
        #expect(one.height >= inner(card).height * 0.9 && card.frame.width > (inner(card).height * screen.width / screen.height) * 1.5)
    }

    @Test("two windows always stand in one row, even where AeroSpace stacks them or stacked would be larger")
    func twoInARow() throws {
        let wide = CGRect(x: 0, y: 0, width: 2400, height: 1000)
        let stacked = WorkspaceInfo(name: "3", windows: [rected(1, "Ghostty", 16, 49, 1696, 520), rected(2, "Ghostty", 16, 581, 1696, 520)], screenIndex: 1, rootLayout: "v_tiles")
        let two = try #require(layout([stacked], frames: [1: wide, 2: wide]).first)
        let one = try #require(two.frames[1]), other = try #require(two.frames[2])
        #expect(one.minY == other.minY && one.maxX <= other.minX)
    }
    private func ghostty(_ ws: String, _ ids: ClosedRange<Int>, _ other: [WindowInfo] = []) -> WorkspaceInfo {
        WorkspaceInfo(name: ws, windows: ids.map { WindowInfo(windowId: $0, appName: "Ghostty", bundleId: "com.Ghostty") } + other, screenIndex: 1, rootLayout: "h_accordion")
    }

    @Test("where AeroSpace's rects are known the card is still the app's windows packed: another app's half of the workspace leaves no gap")
    func rectsDoNotShapeTheCard() throws {
        let ws = WorkspaceInfo(name: "2", windows: [rected(1, "Ghostty", 16, 49, 842, 1052), rected(2, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let card = try #require(layout([ws]).first)
        #expect(card.frames.keys.sorted() == [1] && abs(card.frames[1]!.width - inner(card).width) < 1)
    }

    private func groups(_ n: Int) -> [WorkspaceInfo] {
        (1...n).map { WorkspaceInfo(name: "\($0)", windows: [rected($0, "Ghostty", 16, 49, 842, 1052), rected($0 + 100, "Ghostty", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles") }
    }

    @Test("the cards for the keys: each card on the unrolled row, and in it the app's own windows where they are drawn; no other app's")
    func gridForTheKeys() throws {
        let ws = WorkspaceInfo(name: "2", windows: [rected(1, "Ghostty", 16, 49, 842, 1052), rected(2, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let l = layout(groups(2) + [ws]), card = try #require(l.map(\.grid).last), laid = try #require(l.last)
        #expect(l.count == 3 && card.frame == laid.frame && card.windows.keys.sorted() == [1])
        #expect(card.windows[1] == laid.frames[1]?.offsetBy(dx: laid.frame.minX + L.cardPadding, dy: L.cardChrome - L.cardPadding))
    }

    @Test("workspaces that do not fit slide: the held one whole in the middle, the next cut by the edge, up to the row's ends; a row that fits stands centred")
    func slidingRow() throws {
        let l = layout(groups(5)), w = l[0].frame.width, v = view.width
        func at(_ held: Int) -> [CGFloat] { l.map { $0.frame.minX + L.stripOffset(l, held: held, viewWidth: v) } }
        #expect(l[4].frame.maxX > v && at(0)[0] == 0 && at(0).contains { $0 < v && $0 + w > v })
        #expect(abs(at(2)[2] + w / 2 - v / 2) <= 1 && at(2).contains { $0 < 0 && $0 + w > 0 })
        #expect(abs(at(4)[4] + w - v) <= 1)
        let row = layout(groups(1))
        #expect(abs(row[0].frame.midX + L.stripOffset(row, held: 0, viewWidth: v) - v / 2) <= 1)
    }
}

// MARK: - Store: capture at summon, drop on hide

/// A window with AeroSpace's layout rect, as the owner's branch reports one.
private func framed(_ sizes: [Int: CGSize]) -> [Int: CGRect] { sizes.mapValues { CGRect(origin: .zero, size: $0) } }

private func rected(_ id: Int, _ app: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", layoutRect: CGRect(x: x, y: y, width: w, height: h))
}
