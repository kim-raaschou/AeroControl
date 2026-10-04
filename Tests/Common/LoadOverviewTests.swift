import Testing
@testable import AeroControlKit
@testable import Common

@Suite("AerospaceCommand.argv(for:)")
struct ArgvForActionTests {
    @Test("each action is one AeroSpace command; a move follows the window unless it is quiet", arguments: [
        (AeroControlAction.focusWorkspace("3"), ["workspace", "3"]),
        (.focusWindow(42), ["focus", "--window-id", "42"]),
        (.moveWindow(windowId: 7, toWorkspace: "2"), ["move-node-to-workspace", "--window-id", "7", "--focus-follows-window", "2"]),
        (.moveWindowQuietly(windowId: 7, toWorkspace: "2"), ["move-node-to-workspace", "--window-id", "7", "2"]),
        (.closeWindow(5), ["close", "--window-id", "5"]),
    ])
    func argv(action: AeroControlAction, argv: [String]) {
        #expect(AerospaceCommand.argv(for: action) == argv)
    }
}

@Suite("loadOverview")
struct LoadOverviewTests {
    @Test("orchestrates list commands and builds result")
    func orchestrates() async throws {
        let windowsJson = """
        [{"window-id": 1, "app-name": "Firefox", "app-bundle-id": "org.mozilla.firefox", "workspace": "1", "window-parent-container-layout": "h_tiles", "monitor-id": 1}]
        """
        let workspacesJson = """
        [{"workspace": "1", "monitor-id": 1}, {"workspace": "2", "monitor-id": 1}]
        """
        let runner = ScriptRunner(windows: windowsJson, workspaces: workspacesJson)

        let result = try await loadOverview(using: runner)

        #expect(result.workspaces.count == 2)
        #expect(result.workspaces[0].name == "1")
        #expect(result.workspaces[0].windows.count == 1)
        #expect(result.workspaces[0].windows[0].appName == "Firefox")
        #expect(result.workspaces[1].name == "2")
        #expect(result.workspaces[1].windows.isEmpty)
    }
}

@Suite("loadOverview: layout rects when AeroSpace can give them")
struct LoadOverviewLayoutRectsTests {
    private let withRects = AerospaceCommand.listWindows(layoutRects: true)
    private let plain = AerospaceCommand.listWindows()

    /// An AeroSpace that either knows `%{window-layout-rect}` (the owner's branch) or does not
    /// (every release so far).
    private func aerospace(knowsRects: Bool) -> ScriptRunner {
        let runner = ScriptRunner(workspaces: #"[{"workspace": "1", "monitor-id": 1}]"#)
        runner.acceptsLayoutRects = knowsRects
        return runner
    }

    @Test("every load asks with the variable; an AeroSpace that knows it answers, and the plain read is never used")
    func present() async throws {
        let runner = aerospace(knowsRects: true)
        _ = try await loadOverview(using: runner)
        #expect(runner.commandsRun.contains(withRects) && !runner.commandsRun.contains(plain))
    }

    @Test("an AeroSpace without it says it cannot parse the variable; the plain read follows in the same load, every load, nothing remembered")
    func absent() async throws {
        let runner = aerospace(knowsRects: false)
        _ = try await loadOverview(using: runner)
        _ = try await loadOverview(using: runner)
        #expect(runner.commandsRun.filter { $0 == withRects }.count == 2 && runner.commandsRun.filter { $0 == plain }.count == 2)
    }

    @Test("a failure that is not the variable being unknown is a failure: no plain read hides it")
    func hiccupIsAFailure() async {
        let runner = aerospace(knowsRects: true)
        runner.failNextRects = true
        await #expect(throws: (any Error).self) { try await loadOverview(using: runner) }
        #expect(!runner.commandsRun.contains(plain))
    }
}
