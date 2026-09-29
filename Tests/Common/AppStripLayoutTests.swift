import Testing
import Foundation
@testable import Common

// The app strip: one row of groups (one per workspace holding the app), every tile at its
// own shape, one shared picture height — as large as the view allows, between a fifth and a
// half of the screen. Ported from krn.overview's AppStrip (`cardHeight`).

private func strip(_ groups: [[CGFloat]], view: CGFloat = 1600, panel: CGFloat = 1000, padding: CGFloat = 0) -> AppStripLayout.Layout {
    AppStripLayout.layout(groups: groups, viewWidth: view, panelHeight: panel, tileGap: 14, groupGap: 24, caption: 38,
                          groupPadding: padding)
}

@Suite("AppStripLayout")
struct AppStripLayoutTests {
    @Test("the row fills the view: two groups, every tile at its shape, one height, caption under each")
    func fillsTheView() {
        let s = strip([[1.6, 1.6], [0.8]])
        #expect(s.height == 390)                                                  // floor((1600 - 14 - 24) / 4.0)
        #expect(s.groups.count == 2 && s.groups[0].tiles.count == 2 && s.groups[1].tiles.count == 1)
        #expect(s.groups[0].tiles.map(\.width) == [624, 624] && s.groups[1].tiles[0].width == 312)
        #expect(s.groups.flatMap(\.tiles).allSatisfy { $0.height == 390 + 38 })
        #expect(s.groups[0].width == 624 + 14 + 624 && s.groups[1].x == s.groups[0].width + 24)
        #expect(s.width == 1598 && s.width <= 1600)
    }

    @Test("each group is a plate: padding round its tiles is inside the group and comes out of the pictures' height")
    func groupsArePlates() {
        let s = strip([[1.6, 1.6], [0.8]], padding: 12)
        #expect(s.height == 378)                                                  // floor((1600 - 14 - 24 - 2 * 12 * 2) / 4.0)
        #expect(s.groups[0].tiles.map(\.x) == [12, 12 + 604 + 14] && s.groups[0].tiles.map(\.width) == [604, 604])
        #expect(s.groups[0].x == 0 && s.groups[0].width == 12 + 604 + 14 + 604 + 12)
        #expect(s.groups[1].x == s.groups[0].width + 24 && s.groups[1].tiles[0].x == s.groups[1].x + 12)
        #expect(s.groups[1].width == 326)                                       // 12 + 302 + 12
        #expect(s.width == s.groups[1].x + s.groups[1].width && s.width <= 1600)
    }

    @Test("a wide view stops the pictures at half the screen; a narrow one holds them at a fifth and overflows")
    func bounds() {
        #expect(strip([[1.6]], view: 4000).height == 500)
        let narrow = strip([[1.6, 1.6, 1.6]], view: 300)
        #expect(narrow.height == 200)
        #expect(narrow.width > 300)
    }

    @Test("tiles keep their order and never overlap")
    func order() {
        let s = strip([[1.6, 0.8, 2.4], [1.0, 1.0]])
        let tiles = s.groups.flatMap(\.tiles)
        for (a, b) in zip(tiles, tiles.dropFirst()) { #expect(a.x + a.width <= b.x) }
    }

    @Test("nothing to show is an empty strip")
    func empty() {
        let s = strip([])
        #expect(s.groups.isEmpty && s.width == 0 && s.height == 0)
    }
}
