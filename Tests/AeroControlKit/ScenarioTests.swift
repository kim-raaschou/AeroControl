import CoreGraphics
import Testing
@testable import AeroControlKit
@testable import Common

@MainActor
@Suite("Scenarios: the app from the outside")
struct ScenarioTests {
    @Test("type te, Enter: the Teams window wears the ring, AeroSpace is asked to focus it, and the map narrows on the way")
    func typeToFocus() async {
        let runner = ScriptRunner()
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams", title: "Crew standup", bundleId: "com.teams"),
                                        oneWindow(2, "1", app: "Slack", bundleId: "com.slack"),
                                        oneWindow(3, "2", app: "Code", bundleId: "com.code")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2"]))
        runner.setFocus(windowId: 3, workspace: "2")
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        store.screen = (available: CGSize(width: 1600, height: 1000), frames: [:])
        await store.reload()
        #expect(store.scene.body == .map && store.scene.cards.map(\.workspace.name) == ["1", "2"] && store.scene.ringed == 3)
        for c in "te" { _ = store.handle(.character(c)) }
        #expect(store.scene.cards.map(\.workspace.name) == ["1"] && store.scene.ringed == 1 && store.scene.lane == .query("te", miss: false))
        guard case .focus(let id) = store.handle(.enter) else { Issue.record("Enter focuses nothing"); return }
        store.send(.action(.focusWindow(id)))
        await waitUntil { runner.didRun(["focus", "--window-id", "1"]) }
        #expect(runner.didRun(["focus", "--window-id", "1"]))
    }

    @Test("the strip: a card per workspace holding the app, the app's windows carrying their keys; packed, another app's window is not on it")
    func stripScene() async {
        let runner = ScriptRunner()
        runner.setState(windows: "[" + [oneWindow(1, "1", app: "Teams", bundleId: "com.teams"),
                                        oneWindow(9, "1", app: "Slack", bundleId: "com.slack"),
                                        oneWindow(2, "2", app: "Teams", bundleId: "com.teams")].joined(separator: ",") + "]",
                        workspaces: workspacesJSON(["1", "2", "3"]))
        runner.setFocus(windowId: 9, workspace: "1")
        let store = OverviewStore(runner: runner, nativeSystem: FakeBridge())
        store.screen = (available: CGSize(width: 1600, height: 1000), frames: [:])
        await store.reload()
        _ = store.summonApp(.bundleId("com.teams"))
        let scene = store.scene
        #expect(scene.body == .strip && scene.cards.map(\.workspace.name) == ["1", "2"])
        let tiles = scene.cards.flatMap(\.tiles)
        #expect(tiles.map(\.window.windowId) == [1, 2] && tiles.map(\.key) == ["⌘1", "⌘2"] && tiles.allSatisfy { !$0.faded })
        #expect(scene.lane == .app(name: "Teams", bundleId: "com.teams", summary: AppStripModel.summary(store.stripWindows, marked: store.strip?.marked)))
    }
}
