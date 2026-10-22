import Testing
@testable import AeroControl
@testable import Common

@Suite("AerospaceCommand.argv(for:)")
struct ArgvForActionTests {
    @Test("each action is one AeroSpace command; a move follows the window unless it is quiet", arguments: [
        (AeroControlAction.focusWorkspace("3"), ["workspace", "3"]),
        (.focusWindow(42), ["focus", "--window-id", "42"]),
        (.moveWindow(windowId: 7, toWorkspace: "2"), ["move-node-to-workspace", "--window-id", "7", "--focus-follows-window", "2"]),
        (.moveWindowQuietly(windowId: 7, toWorkspace: "2"), ["move-node-to-workspace", "--window-id", "7", "2"]),
        (.closeWindow(5), ["close", "--window-id", "5"]),
        (.setLayout("h_accordion"), ["layout", "h_accordion"]),
    ])
    func argv(action: AeroControlAction, argv: [String]) {
        #expect(AerospaceCommand.argv(for: action) == argv)
    }
}

@Suite("loadOverview: layout rects when AeroSpace can give them")
struct LoadOverviewLayoutRectsTests {
    private let withRects = AerospaceCommand.listWindows(layoutRects: true)
    private let plain = AerospaceCommand.listWindows()

    @Test("every load asks with the variable; an AeroSpace that knows it answers, and the plain read is never used")
    func present() async throws {
        let aero = FakeAeroSpace(["1": []], knowsRects: true)
        _ = try await loadOverview(using: aero)
        #expect(aero.commands.contains(withRects) && !aero.commands.contains(plain))
    }

    @Test("an AeroSpace without it says it cannot parse the variable; the plain read follows in the same load, every load, nothing remembered")
    func absent() async throws {
        let aero = FakeAeroSpace(["1": []])
        _ = try await loadOverview(using: aero)
        _ = try await loadOverview(using: aero)
        #expect(aero.commands.filter { $0 == withRects }.count == 2 && aero.commands.filter { $0 == plain }.count == 2)
    }
}
