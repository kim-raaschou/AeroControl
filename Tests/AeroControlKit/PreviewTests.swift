import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// MARK: - Metrics & layout with previews

@Suite("metrics — previews")
struct PreviewMetricsTests {
    @Test("preview tiles are 3:2 of the icon size; icon tiles stay square")
    func tileSize() {
        let icons = AeroControlMetrics(iconSize: 48)
        let previews = AeroControlMetrics(iconSize: 48, previews: true)
        #expect(icons.tileSize == CGSize(width: 48, height: 48))
        #expect(previews.tileSize == CGSize(width: 144, height: 96))
        #expect(previews.tileWidth == 144 + 2 * previews.tileCellPadding)
        #expect(previews.tileHeight == 96 + 2 * previews.tileCellPadding)
        #expect(previews.tileHeight > icons.tileHeight)
    }

    @Test("fitting metrics make the padded tile exactly the requested cell width")
    func fittingCell() {
        for previews in [true, false] {
            let m = AeroControlMetrics.fitting(cellWidth: 300, previews: previews)
            #expect(abs(m.tileWidth - 300) < 0.001)
        }
        #expect(AeroControlMetrics.fitting(cellWidth: 300, previews: true).iconSize < 100)
    }

    @Test("a snapshot is fitted into the 3:2 cell with its own aspect ratio, and the focus frame hugs it")
    func fittedPreview() {
        let m = AeroControlMetrics(iconSize: 48, previews: true)
        #expect(m.fittedPreviewSize(CGSize(width: 1000, height: 1000)) == CGSize(width: 96, height: 96))
        #expect(m.fittedPreviewSize(CGSize(width: 600, height: 200)) == CGSize(width: 144, height: 48))
        #expect(m.fittedPreviewSize(.zero) == m.previewSize)
        let gap = AeroControlMetrics.snapshotRingGap
        #expect(m.focusPlateRect(around: CGSize(width: 96, height: 96)) == CGSize(width: 96 + 2 * gap, height: 96 + 2 * gap))
    }

    @Test("weight follows content: empty < few < many")
    func weights() {
        #expect(AeroControlLayout.weight(windowCount: 0) < AeroControlLayout.weight(windowCount: 1))
        #expect(AeroControlLayout.weight(windowCount: 1) < AeroControlLayout.weight(windowCount: 4))
        #expect(AeroControlLayout.weight(windowCount: 4) == 2)
    }

    @Test("row count: 1-3 one row, 4-6 two, 7-12 three")
    func rowCounts() {
        #expect([1, 2, 3].map(AeroControlLayout.rowCount(forCount:)) == [1, 1, 1])
        #expect([4, 5, 6].map(AeroControlLayout.rowCount(forCount:)) == [2, 2, 2])
        #expect([7, 9, 12].map(AeroControlLayout.rowCount(forCount:)) == [3, 3, 3])
        #expect(AeroControlLayout.rowCount(forCount: 0) == 0)
    }

    @Test("partition keeps order, uses every row, and balances weight")
    func partitioning() {
        let rows = AeroControlLayout.partition(weights: [4.2, 0.35, 1, 0.35, 0.35], rowCount: 2)
        #expect(rows == [0..<1, 1..<5])                       // the heavy workspace gets its own row
        let even = AeroControlLayout.partition(weights: [1, 1, 1, 1], rowCount: 2)
        #expect(even == [0..<2, 2..<4])
        let many = AeroControlLayout.partition(weights: [1, 1, 1], rowCount: 5)
        #expect(many.count == 3 && many.allSatisfy { !$0.isEmpty })
    }

    @Test("5 workspaces (18, 0, 1, 0, 0 windows): heavy one alone on top, the rest below, all width used")
    func fiveWorkspaces() {
        let available = CGSize(width: 1624, height: 1050)
        let rows = AeroControlLayout.cardSizes(windowCounts: [18, 0, 1, 0, 0], available: available)
        #expect(rows.count == 2)
        #expect(rows[0].count == 1 && rows[0][0].width == 1624)
        #expect(rows[1].count == 4)
        let gap = AeroControlLayout.cardGap
        let bottom = rows[1].map(\.width).reduce(0, +) + 3 * gap
        #expect(bottom <= available.width && bottom > available.width - 4)
        #expect(rows[1][0].width == AeroControlLayout.emptyCardWidth)     // empty: badge only
        #expect(rows[1][1].width > AeroControlLayout.minCardWidth)         // the one with a window is wide
        let heights = rows[0][0].height + rows[1][0].height + gap
        #expect(heights <= available.height && heights > available.height - 4)
        #expect(rows[0][0].height > rows[1][0].height)                     // the heavy row is taller
        #expect(rows[1][0].height >= AeroControlLayout.minRowHeight)
    }

    @Test("all workspaces non-empty share the width by weight")
    func proportional() {
        let rows = AeroControlLayout.cardSizes(windowCounts: [1, 4], available: CGSize(width: 1000, height: 500))
        #expect(rows.count == 1)
        let w = rows[0].map(\.width)
        #expect(abs(w[1] / w[0] - 2) < 0.05)                           // √4 : √1
    }

    @Test("row heights follow the snapshots: a 2x2 row takes height a one-row row does not need")
    func heightsFollowSnapshots() {
        // Today's five workspaces on the 3440x1440 display: [4, 2] on top, [3, 0, 1] below.
        let rows = AeroControlLayout.cardSizes(windowCounts: [4, 2, 3, 0, 1], available: CGSize(width: 3300, height: 1300))
        #expect(rows.count == 2)
        let top = rows[0][0].height, bottom = rows[1][0].height
        #expect(top > bottom * 1.2)                                       // clearly taller, not the near-even weight split
        #expect(top + bottom + AeroControlLayout.cardGap <= 1300 + 1)
        #expect(bottom >= AeroControlLayout.minRowHeight)
        let tile = AeroControlLayout.tileGrid(windowCount: 4, card: rows[0][0])
        #expect(tile.columns == 2 && tile.width > 480)                    // 2x2 with snapshots over 480 pt wide
    }

    @Test("cell aspect is the median snapshot aspect; four tall columns lay out as one row of tall cells")
    func tallColumns() {
        let tall = CGSize(width: 860, height: 1440)                             // a quarter of an ultrawide
        #expect(abs(AeroControlLayout.cellAspect(snapshotSizes: [tall, tall, tall, tall], fallback: 0.5) - 1440.0 / 860.0) < 0.001)
        #expect(AeroControlLayout.cellAspect(snapshotSizes: [], fallback: 0.5) == 0.5)
        #expect(AeroControlLayout.cellAspect(snapshotSizes: [.zero], fallback: 0.5) == 0.5)
        let card = CGSize(width: 2130, height: 900)
        let grid = AeroControlLayout.tileGrid(windowCount: 4, card: card, aspect: 1440.0 / 860.0)
        #expect(grid.columns == 4)                                               // like AeroSpace laid them out
        #expect(grid.width * 1440 / 860 <= card.height - AeroControlLayout.cardPadding - AeroControlLayout.badgeLane + 1)
    }

    @Test("screen map keeps AeroSpace's arrangement: three columns, the middle one split")
    func screenMap() {
        // Workspace 1 as measured: Arc | Code over Teams | Rio, 16 pt gaps, on 3440x1440.
        let arc = CGRect(x: 16, y: 48, width: 1130, height: 1375)
        let code = CGRect(x: 1162, y: 48, width: 1130, height: 681)
        let teams = CGRect(x: 1162, y: 745, width: 1130, height: 678)
        let rio = CGRect(x: 2308, y: 48, width: 1130, height: 1375)
        let frames = [arc, code, teams, rio]
        let outline = AeroControlLayout.mapBounds(frames: frames)!
        let cells = AeroControlLayout.minimap(frames: frames, bounds: outline, in: CGSize(width: 1000, height: 500))
        #expect(cells.count == 4)
        #expect(abs(cells[0].minX) < 0.01 && abs(cells[3].maxX - 1000) < 0.01)      // spans the box's width
        #expect(cells[0].height > 400 && abs(cells[0].height - cells[3].height) < 0.01) // full-height columns, centered vertically
        #expect(abs(cells[1].minX - cells[2].minX) < 0.01 && cells[2].minY > cells[1].maxY) // Code over Teams
        #expect(cells[1].maxX < cells[3].minX && cells[0].maxX < cells[1].minX)
        let bounds = AeroControlLayout.mapBounds(frames: [arc, code, teams, rio])!
        #expect(abs(bounds.height / bounds.width - 1375.0 / 3422.0) < 0.001)
    }

    @Test("no map for overlapping windows (accordion, fullscreen) or without frames")
    func noMapWhenOverlapping() {
        let full = CGRect(x: 16, y: 48, width: 3408, height: 1375)
        let shifted = CGRect(x: 46, y: 48, width: 3378, height: 1375)                  // accordion padding
        #expect(AeroControlLayout.mapBounds(frames: [full, shifted]) == nil)
        #expect(AeroControlLayout.mapBounds(frames: []) == nil)
        #expect(AeroControlLayout.mapBounds(frames: [full]) == full)
        // Side by side with a gap: no overlap, so a map.
        let left = CGRect(x: 0, y: 0, width: 100, height: 100), right = CGRect(x: 116, y: 0, width: 100, height: 100)
        #expect(AeroControlLayout.mapBounds(frames: [left, right]) == CGRect(x: 0, y: 0, width: 216, height: 100))
    }

    @Test("a floating window may overlap the tiles without costing the workspace its map")
    func floatingDoesNotBreakTheMap() {
        let left = CGRect(x: 0, y: 0, width: 100, height: 100)
        let right = CGRect(x: 116, y: 0, width: 100, height: 100)
        let floater = CGRect(x: 60, y: 20, width: 100, height: 60)        // lies over both
        #expect(AeroControlLayout.mapBounds(frames: [left, right, floater]) == nil)   // no flags: a pile
        let bounds = AeroControlLayout.mapBounds(frames: [left, right, floater],
                                                 floating: [false, false, true])
        #expect(bounds == CGRect(x: 0, y: 0, width: 216, height: 100))     // the floater is inside it
        // Two tiles that genuinely overlap still fall back to the grid, floating or not.
        #expect(AeroControlLayout.mapBounds(frames: [left, left], floating: [false, false]) == nil)
    }

    @Test("a map card scores as one screen-shaped cell, worth more height than a grid of four")
    func mapCardIsOneCell() {
        let asGrid = AeroControlLayout.snapshotArea(cells: [4], widths: [2000], aspects: [0.4], height: 700)
        let asMap = AeroControlLayout.snapshotArea(cells: [1], widths: [2000], aspects: [0.4], height: 700)
        #expect(asMap > asGrid)
        // Two rows: the map row takes height from the grid row when that grows the total area.
        let available = CGSize(width: 3300, height: 1300)
        let rows = AeroControlLayout.cardSizes(windowCounts: [4, 2, 3, 0, 1], aspects: [0.4, 0.4, 0.4, 0.4, 0.4], cells: [1, 1, 3, 0, 1], available: available)
        #expect(rows.count == 2 && rows[0][0].height > rows[1][0].height)
    }

    @Test("tile grid picks the column count that maximizes tile size and never overflows")
    func tileGrid() {
        let wide = CGSize(width: 1624, height: 513)
        let (cols, w) = AeroControlLayout.tileGrid(windowCount: 18, card: wide)
        #expect(cols > 4)                                               // a wide card wants many columns
        let rows = Int((18.0 / Double(cols)).rounded(.up))
        #expect(CGFloat(cols) * w + CGFloat(cols - 1) * AeroControlLayout.tileSpacing <= wide.width - 2 * AeroControlLayout.cardPadding + 1)
        #expect(CGFloat(rows) * w * AeroControlLayout.tileAspect + CGFloat(rows - 1) * AeroControlLayout.tileSpacing
                <= wide.height - AeroControlLayout.cardPadding - AeroControlLayout.badgeLane + 1)
        #expect(AeroControlLayout.tileGrid(windowCount: 1, card: wide).columns == 1)
        #expect(AeroControlLayout.tileGrid(windowCount: 0, card: wide) == (0, 0))
        // Four windows in a wide card: a 2x2 grid loses a few percent of tile width to a
        // strip of four but fills the card, so it wins within the tolerance.
        for fourWide in [CGSize(width: 1600, height: 562), CGSize(width: 2130, height: 650)] {   // the wide ws-1 card as measured
            #expect(AeroControlLayout.tileGrid(windowCount: 4, card: fourWide).columns == 2)
            #expect(AeroControlLayout.tileGrid(windowCount: 2, card: fourWide).columns == 2)   // 1x2 stays: 2x1 would halve the tiles
            #expect(AeroControlLayout.tileGrid(windowCount: 3, card: fourWide).columns == 3)   // 1x3 stays for the same reason
        }
        #expect(AeroControlLayout.tileGrid(windowCount: 1, card: CGSize(width: 500, height: 500), aspect: 1).width == AeroControlLayout.maxIconTile)
    }
}

// MARK: - Store: capture at summon, drop on hide

private final class StubRunner: AerospaceProcessRunner, @unchecked Sendable {
    let windows: String
    init(windows: String) { self.windows = windows }
    func run(_ args: [String]) async throws -> String {
        switch args.first {
        case "list-workspaces": return #"[{"workspace":"1","monitor-id":1}]"#
        case "list-windows": return windows
        default: return ""
        }
    }
    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> { AsyncThrowingStream { _ in } }
}

@MainActor
private final class PreviewBridge: NativeApiBridge {
    var granted = true
    var requested = 0
    var captured: [[Int]] = []
    func appIcon(bundleId: String) -> NSImage { NSImage() }
    func appTerminations() -> AsyncStream<Void> { AsyncStream { _ in } }
    func windowCloseSignals() -> AsyncStream<Void> { AsyncStream { _ in } }
    var canCapturePreviews: Bool { granted }
    func requestPreviewAccess() { requested += 1 }
    func windowPreviews(windowIds: [Int], maxSize: CGSize) async -> [Int: NSImage] {
        captured.append(windowIds)
        return Dictionary(uniqueKeysWithValues: windowIds.map { ($0, NSImage(size: maxSize)) })
    }
    /// Ids in `parked` are off screen (a hidden workspace) and get no frame.
    var parked: Set<Int> = []
    func windowFrames(windowIds: [Int]) -> [Int: CGRect] {
        Dictionary(uniqueKeysWithValues: windowIds.filter { !parked.contains($0) }
            .map { ($0, CGRect(x: 100 * $0, y: 0, width: 100, height: 50)) })
    }
}

private let twoWindows = """
[{"window-id":1,"app-name":"A","app-bundle-id":"a","workspace":"1","window-parent-container-layout":"h_tiles","monitor-id":1},
 {"window-id":2,"app-name":"B","app-bundle-id":"b","workspace":"1","window-parent-container-layout":"h_tiles","monitor-id":1}]
"""

@MainActor
@Suite("OverviewStore — previews")
struct OverviewStorePreviewTests {
    @Test("capturePreviews asks the bridge for exactly the model's windows and stores the images")
    func captures() async {
        let bridge = PreviewBridge()
        let store = OverviewStore(runner: StubRunner(windows: twoWindows), nativeSystem: bridge)
        await store.start()
        #expect(store.previewsAvailable)
        await store.capturePreviews(maxSize: CGSize(width: 480, height: 320))
        #expect(store.previews.count == 2)
        #expect(bridge.captured == [[1, 2]])
        #expect(store.frames["1"]?.keys.sorted() == [1, 2])            // both windows were on screen: workspace recorded
        #expect(Set(store.previews.keys) == [1, 2])
        store.clearPreviews()
        #expect(store.previews.isEmpty)
        store.stop()
    }

    @Test("a hidden workspace keeps the frames from when it was visible; a partly parked one is not recorded")
    func framesSurviveParking() async {
        let bridge = PreviewBridge()
        bridge.parked = [2]                                             // window 2 parked from the start
        let store = OverviewStore(runner: StubRunner(windows: twoWindows), nativeSystem: bridge)
        await store.start()
        #expect(store.frames["1"] == nil)                               // not all windows on screen: nothing recorded
        bridge.parked = []
        await store.capturePreviews(maxSize: CGSize(width: 10, height: 10))   // refreshes frames
        #expect(store.frames["1"]?.count == 2)
        bridge.parked = [1, 2]                                          // the workspace is hidden now
        await store.capturePreviews(maxSize: CGSize(width: 10, height: 10))
        #expect(store.frames["1"]?.count == 2)                          // last visible layout survives
        store.stop()
    }

    @Test("without Screen Recording the store reports previews unavailable and asks on request")
    func permission() async {
        let bridge = PreviewBridge()
        bridge.granted = false
        let store = OverviewStore(runner: StubRunner(windows: twoWindows), nativeSystem: bridge)
        #expect(!store.previewsAvailable)
        store.requestPreviewAccess()
        #expect(bridge.requested == 1)
    }

    @Test("a bridge without capture support (default protocol extension) yields no previews")
    func defaultBridge() async {
        @MainActor final class Plain: NativeApiBridge {
            func appIcon(bundleId: String) -> NSImage { NSImage() }
            func appTerminations() -> AsyncStream<Void> { AsyncStream { _ in } }
            func windowCloseSignals() -> AsyncStream<Void> { AsyncStream { _ in } }
        }
        let store = OverviewStore(runner: StubRunner(windows: twoWindows), nativeSystem: Plain())
        await store.start()
        #expect(!store.previewsAvailable)
        await store.capturePreviews(maxSize: CGSize(width: 10, height: 10))
        #expect(store.previews.isEmpty)
        store.stop()
    }
}
