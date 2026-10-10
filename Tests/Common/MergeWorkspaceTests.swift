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
        #expect(effects == [.run([
            .moveWindowQuietly(windowId: 10, toWorkspace: "2"),
            .moveWindowQuietly(windowId: 11, toWorkspace: "2"),
            .moveWindowQuietly(windowId: 12, toWorkspace: "2"),
            .focusWorkspace("2"),
        ], thenRead: true)])
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
        #expect(effects == [.run([.moveWindowQuietly(windowId: 20, toWorkspace: "3"), .focusWorkspace("3")], thenRead: true)])
    }

    @Test("into an empty workspace the source's layout comes along, set on a tiled window of it focused for that: a stack stays a stack, since the windows arrive one by one in the root; into one with windows it does not, nor from floats alone")
    func keepsTheLayoutIntoEmpty() {
        let float = WindowInfo(windowId: 9, appName: "A", bundleId: "a", isFloating: true)
        let stack = OverviewModel(workspaces: [WorkspaceInfo(name: "1", windows: [float, window(10), window(11)], rootLayout: "h_accordion"), ws("2", window(20)), ws("3")])
        #expect(updateOverview(stack, .action(.mergeWorkspace(source: "1", into: "3"))).1 == [.run([
            .moveWindowQuietly(windowId: 9, toWorkspace: "3"), .moveWindowQuietly(windowId: 10, toWorkspace: "3"), .moveWindowQuietly(windowId: 11, toWorkspace: "3"),
            .focusWorkspace("3"), .focusWindow(10), .setLayout("h_accordion"),
        ], thenRead: true)])
        let minimized = WindowInfo(windowId: 8, appName: "A", bundleId: "a", isHidden: true), full = WindowInfo(windowId: 7, appName: "A", bundleId: "a", isFullscreen: true)
        let mixed = OverviewModel(workspaces: [WorkspaceInfo(name: "1", windows: [minimized, full, float, window(10)], rootLayout: "h_accordion"), ws("3")])
        #expect(updateOverview(mixed, .action(.mergeWorkspace(source: "1", into: "3"))).1 == [.run([
            .moveWindowQuietly(windowId: 8, toWorkspace: "3"), .moveWindowQuietly(windowId: 7, toWorkspace: "3"), .moveWindowQuietly(windowId: 9, toWorkspace: "3"), .moveWindowQuietly(windowId: 10, toWorkspace: "3"),
            .focusWorkspace("3"), .focusWindow(10), .setLayout("h_accordion"),
        ], thenRead: true)])   // the layout is set on a tiled window: a minimized or fullscreen one has a container of its own
        let floats = OverviewModel(workspaces: [WorkspaceInfo(name: "1", windows: [float], rootLayout: "h_accordion"), ws("3")])
        #expect(updateOverview(floats, .action(.mergeWorkspace(source: "1", into: "3"))).1 == [.run([.moveWindowQuietly(windowId: 9, toWorkspace: "3"), .focusWorkspace("3")], thenRead: true)])
        #expect(updateOverview(stack, .action(.mergeWorkspace(source: "1", into: "2"))).1 == [.run([
            .moveWindowQuietly(windowId: 9, toWorkspace: "2"), .moveWindowQuietly(windowId: 10, toWorkspace: "2"), .moveWindowQuietly(windowId: 11, toWorkspace: "2"), .focusWorkspace("2"),
        ], thenRead: true)])
    }
}
