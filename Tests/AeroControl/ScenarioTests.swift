import CoreGraphics
import Testing
@testable import AeroControl
@testable import Common

@MainActor
@Suite("Scenarios: the app from the outside, against a fake AeroSpace")
struct ScenarioTests {
    @Test("type te, Enter: the map narrows to the Teams window, on its workspace as it is laid out, the ring is on it, and AeroSpace focuses it; Escape clears the query and the ring goes back to AeroSpace's focus")
    func typeToFocus() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams", "Crew standup"), win(2, "Slack")], "2": [win(3, "Code")]], focused: 3, layouts: ["1": "v_tiles"])
        let app = await TestApp.onMap(aero)
        #expect(app.scene.body == .map && app.scene.cards.map(\.workspace.name) == ["1", "2"] && app.scene.ringed == 3)
        app.type("te")
        #expect(app.scene.cards.map(\.workspace.name) == ["1"] && app.scene.cards.first?.workspace.rootLayout == "v_tiles" && app.scene.ringed == 1 && app.scene.lane == .query("te", miss: false))
        app.key(.escape)
        #expect(app.scene.lane == .keys && app.scene.cards.count == 2 && app.scene.ringed == 3)
        app.type("te")
        app.key(.enter)
        await app.until { aero.focused == 1 }
    }

    @Test("an app's key with windows on two workspaces opens its strip; → and Enter focus its second window")
    func stripPicks() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(9, "Slack")], "2": [win(2, "Teams")], "3": [win(3, "Code")]], focused: 3)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        #expect(app.scene.body == .strip && app.scene.cards.map(\.workspace.name) == ["1", "2"])
        #expect(app.scene.cards.flatMap(\.tiles).map(\.window.windowId) == [1, 2] && app.scene.ringed == 1 && app.store.visit.query.isEmpty)
        app.key(.move(.window(1)))
        app.key(.enter)
        await app.until { aero.focused == 2 }
    }

    @Test("an app's key with one window focuses it and opens nothing")
    func oneWindowFocuses() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [win(3, "Code")]], focused: 3)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-name=Teams")
        await app.until { aero.focused == 1 && app.store.visit.strip == nil }
    }

    @Test("→ walks onto an empty workspace, which wears the ring; Enter switches AeroSpace to it, and Enter there closes the map and stays")
    func emptyWorkspace() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [], "3": [win(3, "Code")]], focused: 1)
        let app = await TestApp.onMap(aero)
        app.key(.move(.window(1)))
        #expect(app.scene.cards.map(\.ringed) == [false, true, false])
        app.key(.enter)
        await app.until { aero.focusedWorkspace == "2" && aero.focused == nil }
        await app.open("aerocontrol://workspaces")
        #expect(app.scene.cards.map(\.focused) == [false, true, false] && app.scene.cards.flatMap(\.tiles).allSatisfy { !$0.ringed })
        app.key(.enter)
        await app.until { !app.store.visit.visible }
        await app.open("aerocontrol://workspaces")
        #expect(aero.focusedWorkspace == "2" && app.scene.cards.map(\.focused) == [false, true, false] && !aero.commands.contains(["focus", "--window-id", "0"]))
    }

    @Test("a strip opened from the map is a visit of its own, its pictures taken at the strip's size; another app's key opens that app's strip with its own")
    func takeoverTakesItsPictures() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Teams")], "3": [win(9, "Slack")], "4": [win(5, "Code")]], focused: 5)
        let app = await TestApp.onMap(aero)
        let onMap = app.store.pictures.previews[1]?.height ?? 0
        await app.open("aerocontrol://app-id=com.teams")
        await app.until { app.scene.body == .strip && onMap > 0 && (app.store.pictures.previews[1]?.height ?? 0) > onMap }
        await app.open("aerocontrol://workspaces")
        await app.open("aerocontrol://app-id=com.teams")
        #expect(app.bridge.captured.last?.contains(9) == false)
        await app.open("aerocontrol://app-id=com.slack")
        await app.until { app.store.visit.strip?.app == "com.slack" && app.bridge.captured.last?.contains(9) == true }
    }

    @Test("the layout icon on a card switches its workspace between tiles and accordion, keeping the direction, and the card follows")
    func layoutIconToggles() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Code")]], focused: 3, layouts: ["1": "v_tiles"])
        let app = await TestApp.onMap(aero)
        app.store.send(.action(.toggleLayout(workspace: "1")))
        await app.until { aero.layout(of: "1") == "v_accordion" && app.scene.cards.first?.workspace.rootLayout == "v_accordion" && app.mirrors(aero) }
        app.store.send(.action(.toggleLayout(workspace: "1")))
        await app.until { aero.layout(of: "1") == "v_tiles" && app.scene.cards.first?.workspace.rootLayout == "v_tiles" }
        #expect(aero.focused == 3 && app.store.visit.visible)
    }

    @Test("a workspace dropped on another moves its windows there in their order and goes along; into an empty one a stack arrives as a stack, set on a tiled window, never a float or a fullscreen one; into one with windows, or from floats alone, no layout comes; onto itself, nothing")
    func merge() async {
        let aero = FakeAeroSpace(["1": [win(9, "Pad", floating: true), win(8, "Film", fullscreen: true), win(1, "Teams"), win(2, "Slack")], "2": [], "3": [win(3, "Code")],
                                  "5": [win(5, "Note", floating: true)], "6": []], focused: 3, layouts: ["1": "h_accordion", "5": "h_accordion"])
        let app = await TestApp.onMap(aero)
        let held = { (name: String) in app.store.visit.model.workspaces.first { $0.name == name }?.windows.count ?? 0 }
        app.store.send(.merge("1", into: "1"))
        app.store.send(.merge("1", into: "2"))
        await app.until { aero.windows(on: "2") == [9, 8, 1, 2] && aero.layout(of: "2") == "h_accordion" && aero.focusedWorkspace == "2" && held("2") == 4 }
        #expect(aero.commands.contains(["focus", "--window-id", "1"]) && !aero.commands.contains { $0.first == "move-node-to-workspace" && $0.last == "1" })
        app.store.send(.merge("2", into: "3"))
        await app.until { aero.windows(on: "3") == [9, 8, 1, 2, 3] && held("3") == 5 }
        app.store.send(.merge("5", into: "6"))
        await app.until { aero.windows(on: "6") == [5] }
        #expect(aero.layout(of: "3") == "h_tiles" && aero.layout(of: "6") == "h_tiles")
    }

    @Test("the map's key again closes the overview and gives the keyboard back to the app under AeroSpace's focus")
    func mapKeyAgainCloses() async {
        let app = await TestApp.onMap(FakeAeroSpace(["1": [win(1, "Teams")], "2": [win(3, "Code")]], focused: 3))
        await app.open("aerocontrol://workspaces")
        #expect(!app.store.visit.visible && app.host.suffix(2) == [.hide, .activate(bundleId: "com.code")])
    }

    @Test("the strip's app key again moves the marking on, as ⌘` does; another app's key opens that app's strip, the map's key the map")
    func stripKeyAgain() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(4, "Slack")], "2": [win(2, "Teams"), win(5, "Slack")], "3": [win(3, "Code")]], focused: 3)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        let first = app.store.visit.strip?.marked
        await app.open("aerocontrol://app-id=com.teams")
        #expect(app.store.visit.strip?.marked != first && app.store.visit.strip?.app == "com.teams")
        await app.open("aerocontrol://app-name=Slack")
        #expect(app.store.visit.strip?.app == "com.slack" && app.store.visit.visible)
        let slack = app.store.visit.strip?.marked
        await app.open("aerocontrol://app-name=Slack")
        #expect(app.store.visit.strip?.marked != slack && app.store.visit.strip?.app == "com.slack")
        await app.open("aerocontrol://workspaces")
        #expect(app.store.visit.visible && app.scene.body == .map)
        await app.open("aerocontrol://workspaces")
        #expect(!app.store.visit.visible && app.host.last == .activate(bundleId: "com.code"))
    }

    @Test("the query takes what is typed: a digit is text, a leading space is nothing, Backspace takes the last; Escape clears it, then closes the overview, back on the focused app")
    func queryEditing() async {
        let app = await TestApp.onMap(FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")]], focused: 2))
        app.key(.character(" "))
        #expect(app.store.visit.query.isEmpty)
        app.type("te2 ")
        #expect(app.store.visit.query == "te2 ")
        app.key(.backspace); app.key(.backspace)
        #expect(app.store.visit.query == "te")
        app.key(.escape)
        #expect(app.store.visit.query.isEmpty && app.store.visit.visible)
        app.key(.backspace); app.key(.escape)
        #expect(!app.store.visit.visible && app.host.last == .activate(bundleId: "com.slack"))
    }

    @Test("two windows and you are in one: the app's key goes to the other, and back at once; from elsewhere it opens the strip")
    func twoWindowsToggle() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [win(2, "Teams")], "3": [win(3, "Code")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        await app.until { aero.focused == 2 && !app.store.visit.visible }
        await app.open("aerocontrol://app-id=com.teams")
        await app.until { aero.focused == 1 }
        await app.past(AerospaceSync.focusAgainAfter)
        #expect(aero.focused == 1 && aero.commands.filter { $0 == ["focus", "--window-id", "2"] }.count == 1)
        aero.userFocus(3)
        await app.until { app.store.visit.recent.first == 3 }
        await app.open("aerocontrol://app-id=com.teams")
        #expect(app.scene.body == .strip && app.store.visit.visible)
    }

    @Test("Escape after the window you came from was closed leaves the focus where it is and makes its app active")
    func escapeAfterOriginClosed() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")]], focused: 1)
        let app = await TestApp.onMap(aero)
        app.key(.move(.window(1)))
        await app.until { aero.focused == 2 }
        aero.remove(1); aero.announce()
        await app.until { app.store.visit.model.window(1) == nil }
        app.key(.escape)
        #expect(!app.store.visit.visible && !aero.commands.contains(["focus", "--window-id", "1"]) && app.host.last == .activate(bundleId: "com.slack"))
    }

    @Test("in the strip Enter picks the marked window, and Escape goes back to the window you came from")
    func stripEnterAndEscape() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Teams"), win(3, "Teams")], "2": [win(20, "Code")]], focused: 20)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        app.key(.move(.window(1)))
        #expect(marked(app) == 2)
        app.key(.enter)
        await app.until { aero.focused == 2 && !app.store.visit.visible }
        await app.past(AerospaceSync.focusAgainAfter)
        aero.userFocus(20)
        await app.until { app.store.visit.recent.first == 20 }
        await app.open("aerocontrol://app-id=com.teams")
        await app.until { aero.focused != 20 }                                                   // AeroSpace follows the marking
        app.key(.escape)
        await app.until { !app.store.visit.visible && aero.focused == 20 }                      // and goes back with Escape
    }

    @Test("an app with no window is started, and the overview closes; one that will not start is said on the lane")
    func launchAndMissing() async {
        let app = TestApp(aerospace: FakeAeroSpace(["1": [win(1, "Teams")]], focused: 1))
        await app.open("aerocontrol://app-name=Typo")
        #expect(app.host.last == .launch(.name("Typo")) && !app.store.visit.visible)
        app.launchFails(.name("Typo"))
        #expect(app.store.visit.visible && app.scene.body == .nothing && app.scene.lane == .notice(name: "Typo", reason: "no app has this name"))
        app.key(.character("x"))
        #expect(app.scene.lane == .notice(name: "Typo", reason: "no app has this name"))
        app.key(.escape)
        #expect(!app.store.visit.visible)
        await app.open("aerocontrol://workspaces")
        #expect(app.store.visit.visible && app.scene.lane == .keys)                                                      // the next visit forgets it
    }

    private func marked(_ app: TestApp) -> Int? { app.scene.cards.flatMap(\.tiles).first(where: \.ringed)?.window.windowId }

    @Test("the query is the user's: typing asks AeroSpace nothing, a window that appears meanwhile joins the matches, and a miss leaves the whole map")
    func queryIsTheUsers() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams", "Crew standup"), win(2, "Slack")]], focused: 2)
        let app = await TestApp.onMap(aero)
        let asked = aero.commands.count
        app.type("crew")
        #expect(aero.commands.count == asked && app.scene.cards.flatMap(\.tiles).map(\.window.windowId) == [1])
        aero.add(win(4, "Teams", "Crew sync"), to: "1")
        await app.until { app.scene.lane == .query("crew", miss: false) && app.scene.cards.flatMap(\.tiles).map(\.window.windowId) == [1, 4] }
        app.type("zz")
        #expect(app.scene.lane == .query("crewzz", miss: true) && app.scene.cards.flatMap(\.tiles).count == 3)
    }

    @Test("on the map the arrows go round, AeroSpace moving its focus moves the outline and not the ring, and a query starts the ring again")
    func arrowsOnTheMap() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [], "3": [win(3, "Code")]], focused: 2)
        let app = await TestApp.onMap(aero)
        app.key(.move(.window(1)))
        #expect(app.scene.cards.map(\.ringed) == [false, true, false])
        app.key(.move(.window(1))); app.key(.move(.window(1)))
        #expect(app.scene.ringed == 1)
        aero.userFocus(3)
        await app.until { app.scene.ringed == 1 && app.scene.cards.flatMap(\.tiles).first { $0.window.windowId == 3 }?.origin == true }
        app.type("sl"); app.key(.escape)
        #expect(app.scene.ringed == 3)
    }

    @Test("AeroSpace's focus follows the ring, within a workspace and onto another, so AeroSpace's own keys act on the window under the ring")
    func ringTakesAeroSpaceAlong() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Code")]], focused: 1)
        let app = await TestApp.onMap(aero)
        app.key(.move(.window(1)))
        await app.until { app.scene.ringed == 2 && aero.focused == 2 }
        app.key(.move(.window(1)))
        await app.until { aero.focusedWorkspace == "2" && app.store.visit.model.focusedWorkspace == "2" }
        #expect(app.scene.ringed == 3 && app.store.visit.visible && app.scene.cards.map(\.focused) == [false, true])
    }

    @Test("the ring on an empty workspace stays on it when AeroSpace forgets another workspace")
    func emptyRingSurvivesTheList() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [], "3": [win(3, "Code")], "4": []], focused: 1)
        let app = await TestApp.onMap(aero)
        for _ in 1...3 { app.key(.move(.window(1))) }
        #expect(app.scene.cards.last?.ringed == true)
        await app.until { aero.focusedWorkspace == "4" }
        aero.forget("2")
        await app.until { app.scene.cards.map(\.workspace.name) == ["1", "3", "4"] && app.scene.cards.last?.ringed == true }
    }

    @Test("in the strip → steps round, a workspace's name goes to it, typing is no query; a window titled after the app is not one of its")
    func stripKeys() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [win(2, "Teams"), win(9, "Slack", "Teams standup notes")], "3": [win(3, "Teams")], "4": [win(5, "Code")]], focused: 5)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        #expect(app.scene.cards.flatMap(\.tiles).map(\.window.windowId) == [1, 2, 3] && marked(app) == 1)
        app.key(.move(.window(1)))
        #expect(marked(app) == 2)
        app.key(.move(.window(1))); app.key(.move(.window(1)))
        #expect(marked(app) == 1)
        app.key(.character("3"))
        #expect(marked(app) == 3)
        app.key(.character("x"))
        #expect(app.store.visit.query.isEmpty && app.scene.body == .strip)
    }

    @Test("from another app the strip opens on the app's window used last")
    func stripOpensOnLastUsed() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [win(2, "Teams")], "3": [win(3, "Teams")], "4": [win(5, "Code")]], focused: 5)
        let app = TestApp(aerospace: aero)
        await app.until { aero.commands.contains { $0.first == "subscribe" } }
        aero.userFocus(2); aero.userFocus(5)
        await app.until { app.store.visit.recent.prefix(2) == [5, 2] }
        await app.open("aerocontrol://app-id=com.teams")
        #expect(marked(app) == 2)
    }

    @Test("AeroSpace's focus decides while the strip is up: within the app it stays, anywhere else it is over and that app keeps the keyboard; on an empty workspace it is over too")
    func stripFollowsFocus() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(9, "Slack")], "2": [win(2, "Teams")], "3": [win(5, "Code")], "4": []], focused: 5)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        aero.userFocus(2)
        await app.until { app.store.visit.model.focusedWindowId == 2 }
        #expect(app.store.visit.visible && app.scene.body == .strip)
        aero.userFocus(9)
        await app.until { !app.store.visit.visible && app.host.last == .activate(bundleId: "com.slack") }
        await app.open("aerocontrol://app-id=com.teams")
        aero.userWorkspace("4")
        await app.until { !app.store.visit.visible && app.host.last == .hide }
    }

    @Test("the strip opens on the app's window used last other than yours, as ⌘` goes back to it; knowing none, on the one after yours, round to the first; AeroSpace follows the marking, and Escape takes it back; its line names the marked window and its workspace")
    func whereTheStripOpens() async {
        let desk: KeyValuePairs<String, [FakeAeroSpace.Window]> = ["1": [win(1, "Teams", "standup"), win(2, "Teams")], "2": [win(3, "Teams", "plan")], "3": [win(5, "Code")]]
        let aero = FakeAeroSpace(desk, focused: 2)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        #expect(marked(app) == 3 && app.scene.lane == .app(name: "Teams", bundleId: "com.teams", summary: "3 windows on 2 workspaces · plan · ws 2"))
        await app.until { aero.focused == 3 }
        app.key(.escape)
        await app.until { aero.focused == 2 && app.store.visit.recent.first == 2 }
        aero.userFocus(1); aero.userFocus(2)
        await app.until { app.store.visit.recent.prefix(2) == [2, 1] }
        await app.open("aerocontrol://app-id=com.teams")
        #expect(marked(app) == 1 && app.scene.lane == .app(name: "Teams", bundleId: "com.teams", summary: "3 windows on 2 workspaces · standup · ws 1"))
        let wrapped = TestApp(aerospace: FakeAeroSpace(desk, focused: 3))
        await wrapped.open("aerocontrol://app-id=com.teams")
        #expect(marked(wrapped) == 1)
    }

    @Test("pointing marks a window, on the map and in the strip, but only a pointer that moved; in the strip the row stays where it is")
    func pointing() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": [win(3, "Teams")], "3": [win(4, "Teams")], "4": [win(5, "Teams")]], focused: 2)
        let app = await TestApp.onMap(aero)
        app.store.notePointer(CGPoint(x: 5, y: 5))
        app.hover(1, at: CGPoint(x: 5, y: 5))
        #expect(app.scene.ringed == 2)
        app.hover(1, at: CGPoint(x: 9, y: 5))
        #expect(app.scene.ringed == 1)
        await app.open("aerocontrol://workspaces")
        await app.open("aerocontrol://app-id=com.teams")
        let held = app.scene.held
        app.hover(5, at: CGPoint(x: 20, y: 5))
        #expect(marked(app) == 5 && app.scene.held == held)
    }

    @Test("Enter on the window AeroSpace already has focused gives its app the keyboard; on another, AeroSpace's focus does")
    func enterOnFocused() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")]], focused: 2)
        let app = await TestApp.onMap(aero)
        app.key(.enter)
        #expect(app.host.suffix(2) == [.hide, .activate(bundleId: "com.slack")])
        await app.open("aerocontrol://workspaces")
        app.key(.move(.window(-1)))
        app.key(.enter)
        await app.until { app.host.last == .hide && aero.focused == 1 }
    }
}
