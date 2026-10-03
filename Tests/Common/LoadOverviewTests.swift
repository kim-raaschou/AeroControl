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

/// An AeroSpace that either knows `%{window-layout-rect}` (the owner's branch) or does not
/// (every release so far). Records what was asked.
private final class LayoutRectsRunner: AerospaceProcessRunner, @unchecked Sendable {
    let accepts: Bool
    /// The next rects read fails for a reason of its own, not because the variable is unknown.
    var failNextRects = false
    private(set) var ran: [[String]] = []
    init(accepts: Bool) { self.accepts = accepts }

    private func asksForRects(_ args: [String]) -> Bool { args.contains { $0.contains("window-layout-rect") } }

    func run(_ args: [String]) async throws -> String {
        ran.append(args)
        if asksForRects(args), failNextRects { failNextRects = false; throw TestError.failed("socket closed") }
        if asksForRects(args), !accepts { throw TestError.failed("ERROR: Failed to parse <output-format>. Can't parse 'window-layout-rect'.") }
        return args.first == "list-workspaces" ? #"[{"workspace": "1", "monitor-id": 1}]"# : "[]"
    }

    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { $0.finish() }
    }

    enum TestError: Error, CustomStringConvertible {
        case failed(String)
        var description: String { if case .failed(let m) = self { return m }; return "" }
    }
}

@Suite("loadOverview: layout rects when AeroSpace can give them")
struct LoadOverviewLayoutRectsTests {
    private let withRects = AerospaceCommand.listWindows(layoutRects: true)
    private let plain = AerospaceCommand.listWindows()

    @Test("every load asks with the variable; an AeroSpace that knows it answers, and the plain read is never used")
    func present() async throws {
        let runner = LayoutRectsRunner(accepts: true)
        _ = try await loadOverview(using: runner)
        #expect(runner.ran.contains(withRects) && !runner.ran.contains(plain))
    }

    @Test("an AeroSpace without it says it cannot parse the variable; the plain read follows in the same load, every load, nothing remembered")
    func absent() async throws {
        let runner = LayoutRectsRunner(accepts: false)
        _ = try await loadOverview(using: runner)
        _ = try await loadOverview(using: runner)
        #expect(runner.ran.filter { $0 == withRects }.count == 2 && runner.ran.filter { $0 == plain }.count == 2)
    }

    @Test("a failure that is not the variable being unknown is a failure: no plain read hides it")
    func hiccupIsAFailure() async {
        let runner = LayoutRectsRunner(accepts: true)
        runner.failNextRects = true
        await #expect(throws: (any Error).self) { try await loadOverview(using: runner) }
        #expect(!runner.ran.contains(plain))
    }
}
