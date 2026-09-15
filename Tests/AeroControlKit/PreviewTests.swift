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
        #expect(previews.cardHeight > icons.cardHeight)
    }

    @Test("focus plate for icon tiles equals the legacy square plate")
    func focusPlateCompatibility() {
        let m = AeroControlMetrics(iconSize: 48)
        #expect(m.focusPlateRect == CGSize(width: m.focusPlateSize, height: m.focusPlateSize))
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
        #expect(Set(store.previews.keys) == [1, 2])
        store.clearPreviews()
        #expect(store.previews.isEmpty)
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
