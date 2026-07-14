import Testing
@testable import Common

@Suite("AerospaceCommand.argv(for:)")
struct ArgvForActionTests {
    @Test("focusWorkspace maps to workspace command")
    func focusWorkspace() {
        #expect(AerospaceCommand.argv(for: .focusWorkspace("3")) == ["workspace", "3"])
    }

    @Test("focusWindow maps to focus --window-id")
    func focusWindow() {
        #expect(AerospaceCommand.argv(for: .focusWindow(42)) == ["focus", "--window-id", "42"])
    }

    @Test("moveWindow maps to move-node-to-workspace")
    func moveWindow() {
        #expect(
            AerospaceCommand.argv(for: .moveWindow(windowId: 7, toWorkspace: "2"))
                == ["move-node-to-workspace", "--window-id", "7", "--focus-follows-window", "2"]
        )
    }
}

/// Returns canned outputs keyed by subcommand — deterministic stand-in for the process pipe.
private struct FakeRunner: AerospaceProcessRunner {
    let outputs: [String: String]

    func run(_ args: [String]) async throws -> String {
        outputs[args.first ?? ""] ?? ""
    }

    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
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
        let runner = FakeRunner(outputs: [
            "list-windows": windowsJson,
            "list-workspaces": workspacesJson,
        ])

        let result = try await loadOverview(using: runner)

        #expect(result.workspaces.count == 2)
        #expect(result.workspaces[0].name == "1")
        #expect(result.workspaces[0].windows.count == 1)
        #expect(result.workspaces[0].windows[0].appName == "Firefox")
        #expect(result.workspaces[1].name == "2")
        #expect(result.workspaces[1].windows.isEmpty)
    }
}
