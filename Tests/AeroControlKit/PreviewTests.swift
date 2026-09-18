import AppKit
import Testing
@testable import AeroControlKit
@testable import Common

// MARK: - Metrics & layout with previews

private func win(_ id: Int, _ app: String, _ title: String = "") -> WindowInfo {
    WindowInfo(windowId: id, appName: app, bundleId: "com.\(app)", title: title)
}

/// Just the sizes: the layout tests never need a cell's identity.
private func cardSizes(_ windowCounts: [Int], available: CGSize) -> [[CGSize]] {
    AeroControlLayout.cardRows(windowCounts: windowCounts, available: available).map { $0.map(\.size) }
}

@Suite("metrics — previews")
struct PreviewMetricsTests {
    @Test("preview tiles are 3:2 of the icon size; icon tiles stay square")
    func tileSize() {
        let icons = AeroControlMetrics(iconSize: 48)
        let previews = AeroControlMetrics(iconSize: 48, previews: true)
        #expect(icons.tileSize == CGSize(width: 48, height: 48))
        #expect(previews.tileSize == CGSize(width: 144, height: 96))
        #expect(previews.tileWidth == 144 + 2 * previews.tileCellPadding)
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
        #expect(AeroControlMetrics.fit(CGSize(width: 1000, height: 1000), into: m.previewSize) == CGSize(width: 96, height: 96))
        #expect(AeroControlMetrics.fit(CGSize(width: 600, height: 200), into: m.previewSize) == CGSize(width: 144, height: 48))
        #expect(AeroControlMetrics.fit(.zero, into: m.previewSize) == m.previewSize)
        let gap = AeroControlMetrics.snapshotRingGap
        #expect(m.focusPlateRect(around: CGSize(width: 96, height: 96)) == CGSize(width: 96 + 2 * gap, height: 96 + 2 * gap))
    }

    @Test("row count: 1-3 one row, 4-6 two, 7-12 three")
    func rowCounts() {
        #expect([1, 2, 3].map(AeroControlLayout.rowCount(forCount:)) == [1, 1, 1])
        #expect([4, 5, 6].map(AeroControlLayout.rowCount(forCount:)) == [2, 2, 2])
        #expect([7, 9, 12].map(AeroControlLayout.rowCount(forCount:)) == [3, 3, 3])
        #expect(AeroControlLayout.rowCount(forCount: 0) == 0)
    }

    @Test("partition keeps order and splits as evenly as it can, remainder on top")
    func partitioning() {
        #expect(AeroControlLayout.partition(count: 7, rowCount: 3) == [0..<3, 3..<5, 5..<7])
        #expect(AeroControlLayout.partition(count: 4, rowCount: 2) == [0..<2, 2..<4])
        let many = AeroControlLayout.partition(count: 3, rowCount: 5)
        #expect(many.count == 3 && many.allSatisfy { !$0.isEmpty })
        #expect(AeroControlLayout.partition(count: 0, rowCount: 3).isEmpty)
    }

    @Test("5 workspaces (18, 0, 1, 0, 0 windows): even rows, empties narrow, all width used")
    func fiveWorkspaces() {
        let available = CGSize(width: 1624, height: 1050)
        let rows = cardSizes([18, 0, 1, 0, 0], available: available)
        #expect(rows.count == 2)
        #expect(rows.map(\.count) == [3, 2])
        let gap = AeroControlLayout.cardGap
        for row in rows {
            let used = row.map(\.width).reduce(0, +) + CGFloat(row.count - 1) * gap
            #expect(used <= available.width && used > available.width - 4)
        }
        #expect(rows[0][1].width == AeroControlLayout.emptyCardWidth)     // empty: badge only
        #expect(rows[0][0].width == rows[0][2].width)                     // 18 windows and 1: same card
        let heights = rows[0][0].height + rows[1][0].height + gap
        #expect(heights <= available.height && heights > available.height - 4)
        #expect(rows[0][0].height == rows[1][0].height)                   // every row the same height
    }

    @Test("cards that hold windows share a row equally, whatever they hold")
    func equalWidths() {
        let rows = cardSizes([1, 4], available: CGSize(width: 1000, height: 500))
        #expect(rows.count == 1)
        #expect(rows[0][0].width == rows[0][1].width)
        #expect(rows[0].map(\.width).reduce(0, +) + AeroControlLayout.cardGap <= 1000)
    }

    @Test("the layout ignores the snapshots: same counts, same cards")
    func layoutIsPredictable() {
        let available = CGSize(width: 3300, height: 1300)
        let rows = cardSizes([4, 2, 3, 0, 1], available: available)
        #expect(rows.count == 2 && rows.map(\.count) == [3, 2])
        #expect(rows[0][0].height == rows[1][0].height)
        #expect(rows[0][0].height * 2 + AeroControlLayout.cardGap <= available.height + 1)
        let tile = AeroControlLayout.tileGrid(windowCount: 4, card: rows[0][0])
        #expect(tile.columns == 2 && tile.width > 400)                    // 2x2 with roomy snapshots
    }

    /// The filtered overview: the result takes over the grid's geometry, and `cardRows` does
    /// the sizing unchanged — it counts windows and has never known what a workspace is.
    @Test("the filtered grid drops the workspaces with no match and sizes the rest by their matches")
    func filteredGridReusesCardRows() {
        let model = OverviewModel(workspaces: [
            WorkspaceInfo(name: "1", windows: (1...6).map { win($0, "Code") }),
            WorkspaceInfo(name: "2", windows: [win(7, "Mail", "Doctor's note")]),
            WorkspaceInfo(name: "3", windows: (8...11).map { win($0, "Safari", "Docs \($0)") }),
            WorkspaceInfo(name: "4", windows: []),
        ])
        let filtered = model.workspaces(holding: model.matching("Code"))
        #expect(filtered.map(\.name) == ["1"])                               // three workspaces gone

        let available = CGSize(width: 1600, height: 1000)
        let rows = AeroControlLayout.cardRows(windowCounts: filtered.map { $0.windows.count }, available: available)
        #expect(rows.map(\.count) == [1])                                    // one card, the whole screen
        #expect(rows[0][0].size.width == available.width)

        // Two matching workspaces: two cards of equal width, and no sliver for the empty ones,
        // because a filtered grid never holds a workspace with nothing in it.
        let two = model.workspaces(holding: model.matching("do"))          // "Doctor's" and "Docs 8"
        #expect(two.map(\.name) == ["2", "3"])
        let split = AeroControlLayout.cardRows(windowCounts: two.map { $0.windows.count }, available: available)
        #expect(split.map(\.count) == [2])
        #expect(Set(split[0].map(\.size.width)).count == 1)
        #expect(split[0].allSatisfy { $0.size.width > AeroControlLayout.emptyCardWidth })
    }

    /// A filtered row is only as tall as its pictures — plus the caption every filtered tile
    /// wears. A picture cannot grow past its aspect ratio, so a row wider than its content
    /// hands the empty height back; a row already limited by height keeps all of it.
    @Test("a filtered row shrinks to what its tiles use, caption lane included")
    func usedHeightFollowsTheTiles() {
        let aspect = AeroControlLayout.tileAspect
        // One 3:2 window in a wide, tall card: limited by width, so height is left over.
        let wide = AeroControlLayout.usedHeight(windowCounts: [1], widths: [1600], aspects: [aspect], available: 2000)
        let tile = AeroControlLayout.tileGrid(windowCount: 1, card: CGSize(width: 1600, height: 2000), aspect: aspect).width
        let expected = tile * aspect + AeroControlLayout.captionLane + AeroControlLayout.cardPadding + AeroControlLayout.badgeLane
        #expect(abs(wide - expected) < 1)
        #expect(wide < 2000)

        // The same window in a short card is limited by height: nothing to hand back.
        #expect(AeroControlLayout.usedHeight(windowCounts: [1], widths: [1600], aspects: [aspect], available: 400) == 400)

        // A row takes the tallest card's need, not the first's.
        let tallest = AeroControlLayout.usedHeight(windowCounts: [1, 4], widths: [800, 800], aspects: [aspect, aspect], available: 2000)
        let alone = AeroControlLayout.usedHeight(windowCounts: [4], widths: [800], aspects: [aspect], available: 2000)
        #expect(tallest == alone)
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

private let twoWindows = windowsJSON([(1, "1"), (2, "1")])
private let oneWorkspace = workspacesJSON(["1"])

@MainActor private func previewStore(_ bridge: FakeBridge) -> OverviewStore {
    OverviewStore(runner: ScriptRunner(windows: twoWindows, workspaces: oneWorkspace), nativeSystem: bridge)
}
