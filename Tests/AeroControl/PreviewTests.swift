import AppKit
import Testing
@testable import AeroControl
@testable import Common

// MARK: - Metrics & layout with previews

private let screen = CGRect(x: 0, y: 33, width: 1728, height: 1084)

private func win(_ id: Int, _ app: String, _ title: String = "") -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", title: title)
}

@Suite("layout")
struct LayoutTests {
    @Test("a card's tiles are packed inside its inner box at the largest height that fits, each at its window's own shape")
    func packedTiles() {
        let inner = CGSize(width: 1600 - 2 * AeroControlLayout.cardPadding, height: 900 - AeroControlLayout.cardChrome)
        let windows = (1...4).map { win($0, "Code") }, sizes = [1: CGSize(width: 1600, height: 1000), 2: CGSize(width: 800, height: 1000)]
        #expect(AeroControlLayout.ratios(of: windows, sizes: sizes, fallback: 1.5) == [1.6, 0.8, 1.5, 1.5])   // measured, measured, screen, screen
        let frames = AeroControlLayout.packed(windows, frames: sizes.mapValues { CGRect(origin: .zero, size: $0) }, screen: nil, inner: inner, caption: 0).frames
        #expect(frames.count == 4 && frames.values.allSatisfy { CGRect(origin: .zero, size: inner).contains($0) } && abs(frames[2]!.width / frames[2]!.height - 0.8) < 0.02)
        #expect(AeroControlLayout.packed([win(1, "Code")], frames: [:], screen: nil, inner: inner, caption: 0).frames[1]!.height > frames[1]!.height)   // alone, taller
    }
}

@Suite("the tree drawn into a card")
struct TreeLayoutTests {
    private let ws7 = [8243, 8240, 3352, 5022, 8266].map { win($0, "Ghostty") }
    private let inner = CGSize(width: 1000, height: 500)
    /// The owner's workspace 7 as AeroSpace's `%{window-layout-rect}` reports it: screen coordinates, top-left origin,
    /// the visible frame starting under the 33-point menu bar, 16-point outer and 12-point inner gaps.
    private var ws7Rected: [WindowInfo] {
        [rected(8243, "Ghostty", 16, 49, 842, 257), rected(8240, "Ghostty", 16, 318, 842, 251), rected(3352, "Ghostty", 16, 581, 842, 251),
         rected(5022, "Ghostty", 16, 844, 842, 257), rected(8266, "Ghostty", 870, 49, 842, 1052)]
    }

    @Test("a floating window lies over the map where it stands on the screen, at the screen's scale, faint: AeroSpace leaves floats to the window server, which says where")
    func floatingOverTheMap() throws {
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isFloating: true)
        let plain = try #require(AeroControlLayout.treeLayout(ws7Rected, frames: [:], screen: screen, inner: inner))
        let laid = try #require(AeroControlLayout.treeLayout(ws7Rected + [float], frames: [99: CGRect(x: 216, y: 233, width: 1200, height: 800)], screen: screen, inner: inner))
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
        let laid = try #require(AeroControlLayout.treeLayout(ws7Rected + [minimized], frames: [:], screen: screen, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
    }

    @Test("a ghost whose size is unknown (no Screen Recording) takes the screen box and leaves the map standing")
    func ghostWithoutSize() throws {
        let float = WindowInfo(windowId: 99, appName: "Finder", bundleId: "com.apple.finder", isFloating: true)
        let laid = try #require(AeroControlLayout.treeLayout(ws7Rected + [float], frames: [:], screen: screen, inner: inner))
        #expect(laid.frames.count == 6 && laid.ghosts == [99])
        let fitted = AeroControlMetrics.fit(screen.size, into: inner)
        #expect(abs(laid.frames[99]!.width - fitted.width) < 0.01 && abs(laid.frames[99]!.height - fitted.height) < 0.01)
    }

    @Test("a fullscreen window is a ghost the size of the screen; a float larger than the screen is cut to it")
    func fullscreenAndOversizedGhosts() throws {
        let full = WindowInfo(windowId: 98, appName: "Zoom", bundleId: "us.zoom", isFullscreen: true)
        let huge = WindowInfo(windowId: 97, appName: "Big", bundleId: "big", isFloating: true)
        let laid = try #require(AeroControlLayout.treeLayout(ws7Rected + [full, huge], frames: [98: screen, 97: CGRect(x: 0, y: 33, width: 3000, height: 3000)],
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
        let laid = try #require(AeroControlLayout.treeLayout(ws7Rected, frames: [:], screen: screen, inner: inner))
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

    @Test("a window its app will not make as small as its slot is drawn as big as it is, from the slot's corner, over its neighbour, as on the screen; the neighbour stays in its own slot")
    func windowDrawnAtItsSlot() throws {
        let row = [rected(287, "Claude", 16, 49, 418, 1052), rected(9134, "Ghostty", 446, 49, 412, 1052)]
        let scale = AeroControlMetrics.fit(screen.size, into: inner).width / screen.width
        let laid = try #require(AeroControlLayout.treeLayout(row, frames: [287: CGRect(x: 0, y: 0, width: 600, height: 1052)], screen: screen, inner: inner))
        let drawn = try #require(laid.frames[287]), ghostty = try #require(laid.frames[9134])
        #expect(abs(drawn.width - 600 * scale) < 0.01 && abs(drawn.minX - ghostty.minX + 430 * scale) < 0.01)   // the 600 the app holds to, not the slot's 418
    }

    @Test("a window smaller than its slot has not been resized to it yet: it is drawn in the slot AeroSpace gives it")
    func aloneInItsSlot() throws {
        let alone = WorkspaceInfo(name: "9", windows: [rected(1, "GitHub", 16, 49, 1696, 1052)])
        let laid = try #require(AeroControlLayout.treeLayout(alone.windows, frames: [1: CGRect(x: 0, y: 0, width: 842, height: 1052)], screen: screen, inner: CGSize(width: 1000, height: 600)))
        let fitted = AeroControlMetrics.fit(screen.size, into: CGSize(width: 1000, height: 600))
        #expect(abs(laid.frames[1]!.width - fitted.width * 1696 / screen.width) < 1)
    }

    @Test("rects that overlap, an accordion's, cannot be a map: only the front one would show, so the card packs tiles instead")
    func overlappingRectsPackTiles() {
        let same = [rected(1, "Claude", 16, 49, 1696, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        let padded = [rected(1, "Claude", 46, 49, 1636, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)]
        #expect(!AeroControlLayout.mirrors(same) && !AeroControlLayout.mirrors(padded))
        #expect(AeroControlLayout.treeLayout(same, frames: [:], screen: screen, inner: inner)?.frames == AeroControlLayout.packed(same, frames: [:], screen: screen, inner: inner, caption: 0).frames)
    }

    @Test("a tiled window without a rect, or none at all (a release AeroSpace), is no map: the card packs tiles")
    func noRectsNoMap() {
        var windows = ws7Rected
        windows[2] = WindowInfo(windowId: 3352, appName: "Ghostty", bundleId: "com.Ghostty")
        #expect(!AeroControlLayout.mirrors(windows) && !AeroControlLayout.mirrors(ws7))
        #expect(AeroControlLayout.treeLayout(windows, frames: [:], screen: screen, inner: inner)?.frames == AeroControlLayout.packed(windows, frames: [:], screen: screen, inner: inner, caption: 0).frames)
    }

}

@Suite("the map as drawn")
struct MapLayoutTests {
    private let float = WindowInfo(windowId: 9, appName: "C", bundleId: "com.C", isFloating: true)
    private func layout(_ workspaces: [WorkspaceInfo], frames: [Int: CGRect] = [:], filtering: Bool = false) -> [AeroControlLayout.LaidCard] {
        AeroControlLayout.mapLayout(workspaces: workspaces, frames: frames, screens: [1: screen], available: CGSize(width: 1800, height: 1100), filtering: filtering)
    }

    @Test("every card where the lattice put it, its windows where the card draws them, both in the map's space; an empty workspace's card holds one stand-in, keyed by its name, the size of its inner box")
    func cardsAsDrawn() throws {
        let a = WorkspaceInfo(name: "1", windows: [rected(1, "A", 16, 49, 842, 1052), rected(2, "B", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let cards = layout([a, WorkspaceInfo(name: "2", windows: [], screenIndex: 1)])
        #expect(cards[0].frame.minX < cards[1].frame.minX && cards[0].frame.size == cards[1].frame.size)
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
        let a = WorkspaceInfo(name: "1", windows: [rected(1, "A", 16, 49, 842, 1052), rected(2, "B", 870, 49, 842, 1052), float], screenIndex: 1, rootLayout: "h_tiles")
        #expect(layout([a]).first?.ghosts == [9])
        let packed = try #require(layout([a], filtering: true).first)
        #expect(packed.ghosts.isEmpty && packed.frames.count == 3)
    }

    @Test("an accordion's card packs its tiled windows, and a float still lies where it stands on the screen, as a ghost")
    func floatOverAnAccordion() throws {
        let a = WorkspaceInfo(name: "1", windows: [rected(1, "A", 24, 57, 1680, 1035), rected(2, "B", 24, 57, 1680, 1035), float], screenIndex: 1, rootLayout: "h_accordion", isVisible: true)
        let card = try #require(layout([a], frames: [9: CGRect(x: 432, y: 304, width: 864, height: 542)]).first)
        let inner = AeroControlLayout.inner(of: card.frame.size), fitted = AeroControlMetrics.fit(screen.size, into: inner), scale = fitted.width / screen.width
        let origin = AeroControlLayout.tileOrigin(packed: fitted, inner: inner), ghost = try #require(card.frames[9])
        #expect(card.ghosts == [9] && card.frames[1]!.maxX <= card.frames[2]!.minX)
        #expect(abs(ghost.minX - (origin.x + 432 * scale)) < 0.01 && abs(ghost.minY - (origin.y + 271 * scale)) < 0.01 && abs(ghost.width - 864 * scale) < 0.01)
    }

    @Test("a float on a hidden workspace stands where AeroSpace will put it back, as its rect says; without one (a release AeroSpace) it lies in the middle of the card at its own size, not in the corner it is parked in; on a shown one it stands where it is, half off the screen too")
    func parkedFloat() throws {
        let a = WorkspaceInfo(name: "1", windows: [rected(1, "A", 24, 57, 1680, 1035), float], screenIndex: 1, rootLayout: "h_tiles")
        let card = try #require(layout([a], frames: [9: CGRect(x: 1727, y: 1085, width: 1081, height: 842)]).first)
        let inner = AeroControlLayout.inner(of: card.frame.size), fitted = AeroControlMetrics.fit(screen.size, into: inner), scale = fitted.width / screen.width
        let box = CGRect(origin: AeroControlLayout.tileOrigin(packed: fitted, inner: inner), size: fitted), ghost = try #require(card.frames[9])
        #expect(abs(ghost.midX - box.midX) < 0.01 && abs(ghost.midY - box.midY) < 0.01 && abs(ghost.width - 1081 * scale) < 0.01)
        let shown = WorkspaceInfo(name: "1", windows: a.windows, screenIndex: 1, rootLayout: "h_tiles", isVisible: true)
        let halfOff = try #require(layout([shown], frames: [9: CGRect(x: 1200, y: 300, width: 1081, height: 842)]).first?.frames[9])
        #expect(abs(halfOff.minX - (box.minX + 1200 * scale)) < 0.01 && abs(halfOff.maxX - box.maxX) < 0.01)
        let told = WorkspaceInfo(name: "1", windows: [a.windows[0], WindowInfo(windowId: 9, appName: "C", bundleId: "com.C", isFloating: true, layoutRect: CGRect(x: 300, y: 233, width: 1081, height: 842))], screenIndex: 1, rootLayout: "h_tiles")
        let back = try #require(layout([told], frames: [9: CGRect(x: 1727, y: 1085, width: 1081, height: 842)]).first?.frames[9])
        #expect(abs(back.minX - (box.minX + 300 * scale)) < 0.01 && abs(back.minY - (box.minY + 200 * scale)) < 0.01)
    }

    @Test("a workspace of floats only is floats: each stands where it is, none packed")
    func floatsOnly() throws {
        let a = WorkspaceInfo(name: "1", windows: [float, WindowInfo(windowId: 8, appName: "D", bundleId: "com.D", isFloating: true)], screenIndex: 1, isVisible: true)
        let card = try #require(layout([a], frames: [9: CGRect(x: 100, y: 133, width: 600, height: 400), 8: CGRect(x: 900, y: 600, width: 600, height: 400)]).first)
        #expect(card.ghosts == [8, 9] && card.frames[9]!.maxX < card.frames[8]!.minX && card.frames[9]!.maxY < card.frames[8]!.minY)
    }
}

@Suite("the strip's cards")
struct StripLayoutTests {
    private typealias L = AeroControlLayout
    /// The box a card's pictures fill, which its frames are in.
    private let available = CGSize(width: 1702, height: 1124)
    private var view: CGSize { L.usable(available) }
    private func layout(_ groups: [WorkspaceInfo], bundleId: String = "com.Ghostty", frames: [Int: CGRect] = [:], centre: Int? = nil) -> [L.LaidCard] {
        L.stripLayout(groups: groups, bundleId: bundleId, centre: centre, frames: frames, screens: [1: screen], available: available).cards
    }

    @Test("one card or two stand as high as the panel lets them; more share the view's width, three and a half of them seen, so a narrower view makes them lower")
    func cardHeight() {
        func h(_ cards: Int) -> CGFloat { layout(groups(cards))[0].frame.height }
        #expect(h(1) == h(2) && h(5) < h(1) && h(4) == h(5))
    }

    @Test("a card holds the app's windows on its workspace and no other app's, packed inside it; one window alone fills its height")
    func cardHoldsTheAppsWindows() throws {
        let stack = ghostty("3", 1...4, [WindowInfo(windowId: 9, appName: "Code", bundleId: "com.Code")])
        let l = layout([stack, ghostty("4", 5...5)])
        let four = try #require(l.first), box = CGRect(origin: .zero, size: L.inner(of: four.frame.size)).insetBy(dx: -0.5, dy: -0.5)
        #expect(four.frames.keys.sorted() == [1, 2, 3, 4] && four.frames.values.allSatisfy { box.contains($0) })
        #expect((l[1].frames[5]?.height ?? 0) > L.inner(of: l[1].frame.size).height * 0.9)
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
        #expect(one.height >= L.inner(of: card.frame.size).height * 0.9 && card.frame.width > (L.inner(of: card.frame.size).height * screen.width / screen.height) * 1.5)
    }

    @Test("two windows of an accordion, one on top of the other on the screen, stand side by side in one row")
    func accordionPairInOneRow() throws {
        let pair = WorkspaceInfo(name: "3", windows: [rected(1, "Ghostty", 16, 49, 1696, 1052), rected(2, "Ghostty", 16, 49, 1696, 1052)], screenIndex: 1, rootLayout: "h_accordion")
        let card = try #require(layout([pair]).first), one = try #require(card.frames[1]), other = try #require(card.frames[2])
        #expect(one.minY == other.minY && one.maxX <= other.minX)
    }

    @Test("a column beside two stacked windows stands as AeroSpace's balance-sizes would have it: the column half the card, the pair stacked in the other half, two equal rows as wide as their column, so the window that holds a whole column gets the most room")
    func balancedBlock() throws {
        let column = [rected(1, "Ghostty", 16, 49, 330, 1052), rected(2, "Ghostty", 358, 49, 1354, 520), rected(3, "Ghostty", 358, 581, 1354, 520)]
        let card = try #require(layout([WorkspaceInfo(name: "3", windows: column, screenIndex: 1, rootLayout: "h_tiles")]).first)
        let tall = try #require(card.frames[1]), top = try #require(card.frames[2]), bottom = try #require(card.frames[3])
        #expect(abs(tall.width - top.width) <= 1 && abs(tall.height - L.inner(of: card.frame.size).height) < 1 && abs(top.height - bottom.height) <= 1)
        #expect(tall.maxX <= top.minX && top.maxY <= bottom.minY && top.minX == bottom.minX && tall.height > 1.5 * top.height)
    }

    @Test("another app's window inside the app's block, or a floating window of the app's, breaks the mirror: the windows are packed as before, two in one row")
    func holeInTheBlockPacks() throws {
        let split = [rected(1, "Ghostty", 16, 49, 1696, 340), rected(9, "Code", 16, 401, 1696, 340), rected(2, "Ghostty", 16, 753, 1696, 348)]
        let card = try #require(layout([WorkspaceInfo(name: "3", windows: split, screenIndex: 1, rootLayout: "v_tiles")]).first)
        let one = try #require(card.frames[1]), other = try #require(card.frames[2])
        #expect(card.frames.keys.sorted() == [1, 2] && one.minY == other.minY && other.minX - one.maxX < one.width / 4)
        let float = WindowInfo(windowId: 3, appName: "Ghostty", bundleId: "com.Ghostty", isFloating: true, layoutRect: CGRect(x: 400, y: 300, width: 600, height: 400))
        let stacked = WorkspaceInfo(name: "4", windows: [rected(1, "Ghostty", 16, 49, 1696, 520), rected(2, "Ghostty", 16, 581, 1696, 520), float], screenIndex: 1, rootLayout: "v_tiles")
        let three = try #require(layout([stacked]).first)
        #expect(three.frames.count == 3 && three.frames[1]?.minY == three.frames[2]?.minY)
    }
    private func ghostty(_ ws: String, _ ids: ClosedRange<Int>, _ other: [WindowInfo] = []) -> WorkspaceInfo {
        WorkspaceInfo(name: ws, windows: ids.map { WindowInfo(windowId: $0, appName: "Ghostty", bundleId: "com.Ghostty") } + other, screenIndex: 1, rootLayout: "h_accordion")
    }

    @Test("every tile stays inside its card's box, whole: a pair, a stack, a block, a row of four, with AeroSpace's rects or without")
    func tilesStayInTheBox() {
        let stack = WorkspaceInfo(name: "2", windows: [rected(3, "Ghostty", 16, 49, 1696, 520), rected(4, "Ghostty", 16, 581, 1696, 520)], screenIndex: 1, rootLayout: "v_tiles")
        let block = WorkspaceInfo(name: "3", windows: [rected(5, "Ghostty", 16, 49, 842, 1052), rected(6, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        for card in layout([ghostty("1", 1...2), stack, block, ghostty("4", 7...10)]) {
            let box = CGRect(origin: .zero, size: L.inner(of: card.frame.size)).insetBy(dx: -0.5, dy: -0.5)
            #expect(!card.frames.isEmpty && card.frames.values.allSatisfy { box.contains($0) && $0.height >= 1 })
        }
    }

    private func groups(_ n: Int) -> [WorkspaceInfo] {
        (1...n).map { WorkspaceInfo(name: "\($0)", windows: [rected($0, "Ghostty", 16, 49, 842, 1052), rected($0 + 100, "Ghostty", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles") }
    }

    @Test("the cards for the keys: each card on the unrolled row, and in it the app's own windows where they are drawn; no other app's, and the app's one window is its own block, leaving no gap")
    func gridForTheKeys() throws {
        let ws = WorkspaceInfo(name: "2", windows: [rected(1, "Ghostty", 16, 49, 842, 1052), rected(2, "Code", 870, 49, 842, 1052)], screenIndex: 1, rootLayout: "h_tiles")
        let l = layout(groups(2) + [ws]), card = try #require(l.map(\.grid).last), laid = try #require(l.last)
        #expect(l.count == 3 && card.frame == laid.frame && card.windows.keys.sorted() == [1])
        #expect(card.windows[1] == laid.frames[1]?.offsetBy(dx: laid.frame.minX + L.cardPadding, dy: L.cardChrome - L.cardPadding))
        #expect(abs(laid.frames[1]!.width - L.inner(of: laid.frame.size).width) < 1)                             // the app's rects do not shape the card
    }

    @Test("workspaces that do not fit slide: the held one whole in the middle, the next cut by the edge, up to the row's ends; a row that fits stands centred")
    func slidingRow() throws {
        func at(_ held: Int) -> [CGFloat] { layout(groups(5), centre: held + 1).map(\.frame.minX) }
        let w = layout(groups(5), centre: 1)[0].frame.width, v = view.width
        #expect(at(0)[4] + w > v && at(0)[0] == 0 && at(0).contains { $0 < v && $0 + w > v })
        #expect(abs(at(2)[2] + w / 2 - v / 2) <= 1 && at(2).contains { $0 < 0 && $0 + w > 0 })
        #expect(abs(at(4)[4] + w - v) <= 1)
        #expect(abs(layout(groups(1), centre: 1)[0].frame.midX - v / 2) <= 1)
    }
}

/// A window with AeroSpace's layout rect, as the owner's branch reports one.
private func rected(_ id: Int, _ app: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", layoutRect: CGRect(x: x, y: y, width: w, height: h))
}
