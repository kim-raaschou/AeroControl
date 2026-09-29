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
    @Test("a card's weight has three steps: empty, ordinary, crowded")
    func weights() {
        #expect([0, 1, 3, 4, 9].map(AeroControlLayout.weight(forCount:)) == [0, 1, 1, 2, 2])
    }

    @Test("the grid options carry the overview's constants and the screen's shape")
    func gridOptions() {
        let o = AeroControlLayout.cardGridOptions(for: CGSize(width: 3000, height: 2000), emptyWidth: 60, caption: 38)
        #expect(o.gap == AeroControlLayout.cardGap && o.tileGap == AeroControlLayout.tileSpacing)
        #expect(o.chrome == AeroControlLayout.cardPadding + AeroControlLayout.badgeLane)
        #expect(o.narrow == 60 && o.caption == 38)
        #expect(o.tileRatio == 1.5 && o.cardShape == 1.5)
    }

    @Test("a card's tiles are packed inside its inner box, each at its window's own shape")
    func packedTiles() {
        let inner = AeroControlLayout.innerSize(of: CGSize(width: 1600, height: 900))
        let windows = (1...4).map { win($0, "Code") }
        let sizes: [Int: CGSize] = [1: CGSize(width: 1600, height: 1000), 2: CGSize(width: 800, height: 1000)]
        let ratios = AeroControlLayout.ratios(of: windows, sizes: sizes, fallback: 1.5)
        #expect(ratios == [1.6, 0.8, 1.5, 1.5])                                  // measured, measured, screen, screen
        let packed = AeroControlLayout.packTiles(ratios: ratios, inner: inner, caption: 0)
        #expect(packed.tiles.count == 4 && packed.width <= inner.width && packed.height <= inner.height)
        #expect(abs(packed.tiles[1].width / packed.tiles[1].height - 0.8) < 0.02)  // the portrait one stays portrait
    }
}

// MARK: - Store: capture at summon, drop on hide

private let twoWindows = windowsJSON([(1, "1"), (2, "1")])
private let oneWorkspace = workspacesJSON(["1"])

@MainActor private func previewStore(_ bridge: FakeBridge) -> OverviewStore {
    OverviewStore(runner: ScriptRunner(windows: twoWindows, workspaces: oneWorkspace), nativeSystem: bridge)
}
