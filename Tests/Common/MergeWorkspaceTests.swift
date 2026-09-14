import Testing
@testable import Common

private func window(_ id: Int) -> WindowInfo { WindowInfo(windowId: id, appName: "A", bundleId: "a") }
private func ws(_ name: String, _ windows: WindowInfo...) -> WorkspaceInfo { WorkspaceInfo(name: name, windows: windows) }

@Suite("update — merge workspace")
struct MergeWorkspaceTests {
    let state = OverviewModel(
        workspaces: [ws("1", window(10), window(11), window(12)), ws("2", window(20)), ws("3")],
        focusedWindowId: 10,
        focusedWorkspace: "1"
    )

    @Test("merge expands to quiet moves in on-screen order, then focuses the target")
    func expandsInOrder() {
        let (new, effects) = updateOverview(state, .action(.mergeWorkspace(source: "1", into: "2")))
        #expect(new == state)   // AeroSpace is the source of truth; the reload updates the model
        #expect(effects == [.runSequence([
            .moveWindowQuietly(windowId: 10, toWorkspace: "2"),
            .moveWindowQuietly(windowId: 11, toWorkspace: "2"),
            .moveWindowQuietly(windowId: 12, toWorkspace: "2"),
            .focusWorkspace("2"),
        ])])
    }

    @Test("merging a workspace into itself does nothing")
    func sameWorkspace() {
        let (_, effects) = updateOverview(state, .action(.mergeWorkspace(source: "1", into: "1")))
        #expect(effects.isEmpty)
    }

    @Test("merging an empty or unknown source does nothing")
    func emptySource() {
        #expect(updateOverview(state, .action(.mergeWorkspace(source: "3", into: "1"))).1.isEmpty)
        #expect(updateOverview(state, .action(.mergeWorkspace(source: "9", into: "1"))).1.isEmpty)
    }

    @Test("merge into an empty workspace is allowed")
    func intoEmpty() {
        let (_, effects) = updateOverview(state, .action(.mergeWorkspace(source: "2", into: "3")))
        #expect(effects == [.runSequence([.moveWindowQuietly(windowId: 20, toWorkspace: "3"), .focusWorkspace("3")])])
    }
}

@Suite("AerospaceCommand argv (moves)")
struct MoveArgvTests {
    @Test("moveWindow follows focus; moveWindowQuietly does not")
    func focusFlag() {
        #expect(AerospaceCommand.argv(for: .moveWindow(windowId: 7, toWorkspace: "2"))
            == ["move-node-to-workspace", "--window-id", "7", "--focus-follows-window", "2"])
        #expect(AerospaceCommand.argv(for: .moveWindowQuietly(windowId: 7, toWorkspace: "2"))
            == ["move-node-to-workspace", "--window-id", "7", "2"])
    }
}

@Suite("parseWindows — title")
struct WindowTitleParseTests {
    @Test("window-title is carried into WindowInfo; missing title becomes empty")
    func title() throws {
        let json = """
        [
          {"window-id": 1, "app-name": "Arc", "app-bundle-id": "b", "window-title": "Inbox", "workspace": "1", "window-parent-container-layout": "h_tiles", "monitor-id": 1},
          {"window-id": 2, "app-name": "kitty", "app-bundle-id": "k", "workspace": "1", "window-parent-container-layout": "h_tiles", "monitor-id": 1}
        ]
        """
        let parsed = try parseWindows(json: json)
        #expect(parsed[0].window.title == "Inbox")
        #expect(parsed[1].window.title == "")
    }
}
