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

    @Test("5 workspaces lay out as 3 + 2 in equal cards that fit the screen")
    func fiveWorkspaces() {
        #expect(AeroControlLayout.columns(forCount: 5) == 3)
        #expect(AeroControlLayout.rows(forCount: 5) == 2)
        let card = AeroControlLayout.cardSize(count: 5, available: CGSize(width: 1486, height: 960))
        let gap = AeroControlLayout.cardGap
        // Uses the whole area: within a point of the width and height in both directions.
        #expect(card.width * 3 + gap * 2 <= 1486 && card.width * 3 + gap * 2 > 1486 - 3)
        #expect(card.height * 2 + gap <= 960 && card.height * 2 + gap > 960 - 3)
    }

    @Test("grid shape for other counts")
    func gridShapes() {
        #expect(AeroControlLayout.columns(forCount: 1) == 1 && AeroControlLayout.rows(forCount: 1) == 1)
        #expect(AeroControlLayout.columns(forCount: 2) == 2 && AeroControlLayout.rows(forCount: 2) == 1)
        #expect(AeroControlLayout.columns(forCount: 4) == 2 && AeroControlLayout.rows(forCount: 4) == 2)
        #expect(AeroControlLayout.columns(forCount: 9) == 3 && AeroControlLayout.rows(forCount: 9) == 3)
        #expect(AeroControlLayout.columns(forCount: 0) == 0 && AeroControlLayout.cardSize(count: 0, available: CGSize(width: 100, height: 100)) == .zero)
    }

    @Test("tiles inside a card fill it and never overflow")
    func tilesFitCard() {
        let card = CGSize(width: 479, height: 468)
        for count in 1...9 {
            let w = AeroControlLayout.tileWidth(windowCount: count, card: card)
            let cols = AeroControlLayout.columns(forCount: count), rows = AeroControlLayout.rows(forCount: count)
            let totalW = CGFloat(cols) * w + CGFloat(cols - 1) * AeroControlLayout.tileSpacing
            let totalH = CGFloat(rows) * w * AeroControlLayout.tileAspect + CGFloat(rows - 1) * AeroControlLayout.tileSpacing
            #expect(w >= AeroControlLayout.minTileWidth)
            #expect(totalW <= card.width - 2 * AeroControlLayout.cardPadding + 1 || w == AeroControlLayout.minTileWidth)
            #expect(totalH <= card.height - AeroControlLayout.cardPadding - AeroControlLayout.badgeLane + 1 || w == AeroControlLayout.minTileWidth)
        }
        #expect(AeroControlLayout.tileWidth(windowCount: 0, card: card) == 0)
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
private func waitUntil(_ cond: () -> Bool) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if cond() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
@Suite("OverviewStore — previews")
struct OverviewStorePreviewTests {
    @Test("capturePreviews asks the bridge for exactly the model's windows and stores the images")
    func captures() async {
        let bridge = PreviewBridge()
        let store = OverviewStore(runner: StubRunner(windows: twoWindows), nativeSystem: bridge)
        await store.start()
        #expect(store.previewsAvailable)
        store.capturePreviews(maxSize: CGSize(width: 480, height: 320))
        await waitUntil { store.previews.count == 2 }
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
        store.capturePreviews(maxSize: CGSize(width: 10, height: 10))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(store.previews.isEmpty)
        store.stop()
    }
}
