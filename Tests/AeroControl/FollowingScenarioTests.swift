import CoreGraphics
import Testing
@testable import AeroControl
@testable import Common

@MainActor
@Suite("Scenarios: following AeroSpace, and the pictures")
struct FollowingScenarioTests {
    private func reads(_ aero: FakeAeroSpace) -> Int { aero.commands.filter { $0.first == "list-windows" && !$0.contains("--focused") }.count }
    private func fills(_ app: TestApp, _ id: Int) -> Bool {
        app.scene.cards.flatMap(\.tiles).first { $0.window.windowId == id }.map { app.bridge.filling[id] == CGSize(width: 2 * $0.picture.width, height: 2 * $0.picture.height) } ?? false
    }
    private func shaped(_ app: TestApp, _ id: Int, _ ratio: CGFloat) -> Bool {
        app.store.pictures.previews[id].map { abs(CGFloat($0.width) / CGFloat($0.height) - ratio) < 0.02 } ?? false
    }

    @Test("one connection to AeroSpace for as long as AeroControl runs: hidden, a focus change is only remembered; shown, every change is read, and an event that changes nothing reads nothing")
    func listening() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [win(2, "Code")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.until { aero.commands.contains { $0.first == "subscribe" } }
        aero.userFocus(2)
        await app.until { app.store.visit.recent.first == 2 }
        await app.past(AerospaceSync.readAfter)
        #expect(reads(aero) == 0)
        await app.open("aerocontrol://workspaces")
        aero.add(win(4, "Slack"), to: "1")
        await app.until { app.scene.cards.flatMap(\.tiles).map(\.window.windowId).contains(4) }
        let read = reads(aero)
        aero.announce("mode-changed")
        await app.past(AerospaceSync.readAfter)
        #expect(reads(aero) == read)
        await app.open("aerocontrol://workspaces")
        #expect(aero.commands.filter { $0.first == "subscribe" }.count == 1)
    }

    @Test("the map is AeroSpace, live: whatever is done in AeroSpace while it is up, a bound key's command run after its event or a focus moved, the map shows as AeroSpace has it")
    func mapIsAeroSpaceLive() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Code")], "3": []], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        #expect(app.mirrors(aero))
        aero.userFocus(3)
        await app.until { app.mirrors(aero) && aero.focusedWorkspace == "2" }
        aero.userWorkspace("3")
        await app.until { app.mirrors(aero) && aero.focusedWorkspace == "3" }
        aero.add(win(4, "Mail"), to: "3")
        await app.until { app.mirrors(aero) && aero.windows(on: "3") == [4] }
        aero.bound { $0.relayout("1", "h_accordion") }
        await app.until { app.mirrors(aero) && aero.layout(of: "1") == "h_accordion" }
        aero.bound { $0.shift(2, to: "2") }
        await app.until { app.mirrors(aero) && aero.windows(on: "2") == [2, 3] }
        aero.bound { $0.remove(1) }
        await app.until { app.mirrors(aero) && aero.windows(on: "1").isEmpty }
    }

    @Test("the strip is AeroSpace, live: every window on its workspaces, the other apps' faded; the app's windows moved, a stack made, a window closed by AeroSpace's keys while it is up, the strip shows as AeroSpace has it")
    func stripIsAeroSpaceLive() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Teams")], "3": [win(4, "Teams")], "4": [win(5, "Code")]], focused: 5)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        #expect(app.scene.cards.map(\.workspace.name) == ["1", "2", "3"] && app.scene.cards.first?.tiles.map(\.faded) == [false, true] && app.mirrors(aero))
        aero.bound { $0.shift(4, to: "2") }
        await app.until { app.mirrors(aero) && app.scene.cards.map(\.workspace.name) == ["1", "2"] }
        aero.bound { $0.relayout("2", "h_accordion") }
        await app.until { app.mirrors(aero) && aero.layout(of: "2") == "h_accordion" }
        aero.bound { $0.remove(3) }
        await app.until { app.mirrors(aero) && aero.windows(on: "2") == [4] }
        #expect(app.store.visit.visible && app.scene.body == .strip)
    }

    @Test("a read that changes nothing redraws nothing; one that changes the windows does")
    func redrawsOnlyChanges() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        let redraws = ModelInvalidationCounter(app.store), measured = app.bridge.measured
        aero.announce()
        await app.until { app.bridge.measured >= measured + 2 }
        #expect(redraws.count == 0)
        aero.add(win(4, "Slack"), to: "1")
        await app.until { redraws.count > 0 }
    }

    @Test("the strip takes its pictures once: every window of its workspaces and nothing else; closing drops them")
    func stripPictures() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(9, "Slack")], "2": [win(2, "Teams"), win(3, "Teams")], "3": [win(7, "Slack")], "4": [win(5, "Code")]], focused: 5)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        #expect(app.bridge.captured == [[1, 9, 2, 3]] && app.store.pictures.previews[9] != nil && app.store.pictures.previews[7] == nil)
        await app.open("aerocontrol://workspaces")
        #expect(!app.store.visit.visible && app.store.pictures.previews.isEmpty && app.store.pictures.frames.isEmpty)
    }

    @Test("each picture is taken just covering the pixels its tile draws: on the map, and again at the strip's when a strip takes over")
    func picturesAtTheirTilesPixels() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Teams")], "3": [win(4, "Teams")]], focused: 2)
        let app = TestApp(aerospace: aero)
        let drawn = { app.scene.cards.flatMap(\.tiles).allSatisfy { t in app.bridge.filling[t.window.windowId] == CGSize(width: 2 * t.picture.width, height: 2 * t.picture.height) } }
        await app.open("aerocontrol://workspaces")
        let onMap = app.bridge.filling[1]
        #expect(app.scene.body == .map && drawn())
        await app.open("aerocontrol://app-id=com.teams")
        await app.until { app.scene.body == .strip && drawn() && app.bridge.filling[1] != onMap }
    }

    @Test("a workspace's pictures land together once all of its windows are taken, in reading order: one that is in waits for those before it")
    func picturesLandByCard() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Code")], "3": [win(4, "Mail")]], focused: 1)
        let app = TestApp(aerospace: aero)
        app.bridge.holdAfter = 3
        let opening = Task { await app.open("aerocontrol://workspaces") }
        await app.until { app.bridge.isHolding }
        #expect(app.store.pictures.previews.keys.sorted() == [1, 2, 3])
        app.bridge.release()
        await opening.value
        #expect(app.store.pictures.previews.keys.sorted() == [1, 2, 3, 4])
        await app.open("aerocontrol://workspaces")
        app.bridge.blank = [2]
        let again = Task { await app.open("aerocontrol://workspaces") }
        await app.until { app.bridge.isHolding }
        #expect(app.store.pictures.previews.isEmpty)
        app.bridge.release()
        await again.value
        #expect(app.store.pictures.previews.keys.sorted() == [1, 3, 4])
    }

    @Test("after a move the windows' sizes land at once, and only the window left behind is taken again: larger, as its tile grew, then in its new shape")
    func moveRetakesOnlyChanged() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Code")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        #expect(app.bridge.captured == [[1, 2, 3]])
        app.bridge.sizes[2] = CGSize(width: 600, height: 200)
        app.key(.moveToWorkspace("2"))
        await app.until { app.store.pictures.frames[2]?.width == 600 }
        await app.until { shaped(app, 2, 3) }
        #expect(app.bridge.captured.dropFirst().allSatisfy { $0 == [2] } && shaped(app, 1, 1.5))
    }

    @Test("a window left alone in an accordion keeps its shape, but its tile grows, so it is taken again at the tile's new pixels")
    func leftAloneTakenLarger() async {
        let aero = FakeAeroSpace(["7": [win(1, "Brave"), win(2, "Claude")], "1": [win(3, "Arc")]], focused: 2, layouts: ["7": "h_accordion"])
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        let before = app.bridge.filling[1]
        app.key(.moveToWorkspace("1"))
        await app.until { app.scene.cards.first?.tiles.count == 1 && fills(app, 1) && app.bridge.filling[1] != before }
    }

    @Test("a query that leaves fewer cards draws them larger, and their pictures are taken again to match")
    func filteredTakenLarger() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Code")], "3": [win(4, "Mail")], "4": [win(5, "Notes")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        let before = app.bridge.filling[3]
        app.type("code")
        await app.until { app.scene.cards.count == 1 && fills(app, 3) && app.bridge.filling[3] != before }
    }

    @Test("a window that resizes in steps is taken again once, after it stops, in its last shape, however many events come on the way")
    func resizingTakenOnce() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        aero.announce()
        for width in [400.0, 500.0, 600.0] {
            try? await Task.sleep(for: .milliseconds(35))
            app.bridge.sizes[2] = CGSize(width: width, height: 200)
            if width == 500 { aero.announce() }
        }
        await app.until { app.bridge.captured.count == 2 }
        await app.past(AerospaceSync.readAgainAfter)
        #expect(app.bridge.captured == [[1, 2], [2]] && app.store.pictures.frames[2]?.width == 600)
    }

    @Test("a change that comes while pictures are being taken again loses nothing: the next refresh takes them")
    func overlappingRefreshes() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        app.bridge.holdAfter = 0
        app.bridge.sizes[2] = CGSize(width: 600, height: 200)
        aero.announce()
        await app.until { app.bridge.isHolding }
        app.bridge.holdAfter = nil
        aero.announce()
        app.bridge.release()
        await app.until { shaped(app, 2, 3) }
    }

    @Test("AeroSpace's events coming close together do not hold the sizes back")
    func eventsDoNotHoldSizesBack() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        app.bridge.sizes[2] = CGSize(width: 600, height: 200)
        for _ in 0..<6 {
            aero.announce()
            try? await Task.sleep(for: .milliseconds(100))
        }
        #expect(app.store.pictures.frames[2]?.width == 600)
    }

    @Test("a window that appears while the overview is up gets a picture; a refresh that changes nothing takes none")
    func newWindowGetsPicture() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        aero.add(win(4, "Slack"), to: "1")
        await app.until { app.bridge.captured.last == [4] }
        let measured = app.bridge.measured
        aero.announce()
        await app.until { app.bridge.measured >= measured + 2 }
        #expect(app.bridge.captured.count == 2)
    }
}
