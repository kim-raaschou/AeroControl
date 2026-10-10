import Testing
@testable import AeroControlKit
@testable import Common

@MainActor
@Suite("Scenarios: the app from the outside, against a fake AeroSpace")
struct ScenarioTests {
    @Test("type te, Enter: the map narrows to the Teams window, the ring is on it, and AeroSpace focuses it; Escape clears the query and the ring goes back to AeroSpace's focus")
    func typeToFocus() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams", "Crew standup"), win(2, "Slack")], "2": [win(3, "Code")]], focused: 3)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        #expect(app.scene.body == .map && app.scene.cards.map(\.workspace.name) == ["1", "2"] && app.scene.ringed == 3)
        app.type("te")
        #expect(app.scene.cards.map(\.workspace.name) == ["1"] && app.scene.ringed == 1 && app.scene.lane == .query("te", miss: false))
        app.key(.escape)
        #expect(app.scene.lane == .keys && app.scene.cards.count == 2 && app.scene.ringed == 3)
        app.type("te")
        app.key(.enter)
        await app.settled()
        #expect(aero.focused == 1)
    }

    @Test("an app's key with windows on two workspaces opens its strip; ⌘2 focuses its second window")
    func stripPicks() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(9, "Slack")], "2": [win(2, "Teams")], "3": [win(3, "Code")]], focused: 3)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-id=com.teams")
        #expect(app.scene.body == .strip && app.scene.cards.map(\.workspace.name) == ["1", "2"])
        #expect(app.scene.cards.flatMap(\.tiles).map(\.key) == ["⌘1", "⌘2"] && app.scene.ringed == app.store.strip?.marked && app.store.filter.isEmpty)
        app.key(.commandKey(2))
        await app.settled()
        #expect(aero.focused == 2)
    }

    @Test("an app's key with one window focuses it and opens nothing")
    func oneWindowFocuses() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [win(3, "Code")]], focused: 3)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://app-name=Teams")
        await app.settled()
        #expect(aero.focused == 1 && app.store.strip == nil)
    }

    @Test("⇧⌘ and a workspace's name moves the window under the ring there, and the map shows it moved; a new name makes the workspace")
    func moveToWorkspace() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [win(3, "Code")]], focused: 3)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        app.key(.moveToWorkspace("1"))
        await app.settled()
        #expect(aero.windows(on: "1") == [1, 3] && app.scene.cards.first { $0.workspace.name == "1" }?.tiles.map(\.window.windowId) == [1, 3])
        app.key(.moveToWorkspace("X"))
        await app.settled()
        #expect(aero.windows(on: "X") == [3] && app.scene.cards.map(\.workspace.name).contains("X"))
    }

    @Test("⌘W closes the window under the ring; the map loses it and the overview stays")
    func closeRinged() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")]], focused: 2)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        app.closeRinged()
        await app.settled()
        #expect(aero.windows(on: "1") == [1] && app.scene.cards.flatMap(\.tiles).map(\.window.windowId) == [1] && app.scene.body == .map)
    }

    @Test("→ walks onto an empty workspace, which wears the ring; Enter switches AeroSpace to it")
    func emptyWorkspace() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams")], "2": [], "3": [win(3, "Code")]], focused: 1)
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        app.key(.move(.window(1)))
        #expect(app.scene.cards.map(\.ringed) == [false, true, false])
        app.key(.enter)
        await app.settled()
        #expect(aero.focusedWorkspace == "2" && aero.focused == nil)
        await app.open("aerocontrol://workspaces")
        #expect(app.scene.cards.map(\.focused) == [false, true, false] && app.scene.cards.flatMap(\.tiles).allSatisfy { !$0.ringed })
    }

    @Test("a stack merged into an empty workspace arrives as a stack")
    func mergeStack() async {
        let aero = FakeAeroSpace(["1": [win(1, "Teams"), win(2, "Slack")], "2": []], focused: 1, layouts: ["1": "h_accordion"])
        let app = TestApp(aerospace: aero)
        await app.open("aerocontrol://workspaces")
        app.store.send(.action(.mergeWorkspace(source: "1", into: "2")))
        await app.settled()
        #expect(aero.windows(on: "2") == [1, 2] && aero.layout(of: "2") == "h_accordion")
    }

    @Test("⌘/ lays the keys over the overview; Escape takes them away before it does anything else")
    func help() async {
        let app = TestApp(aerospace: FakeAeroSpace(["1": [win(1, "Teams")]], focused: 1))
        await app.open("aerocontrol://workspaces")
        app.key(.help)
        #expect(app.scene.help)
        app.key(.escape)
        #expect(!app.scene.help && app.scene.body == .map)
    }
}
