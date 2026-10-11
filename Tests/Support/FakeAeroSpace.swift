import Testing
import Foundation
@testable import AeroControl
@testable import Common

final class FakeAeroSpace: AerospaceProcessRunner, @unchecked Sendable {
    struct Window: Equatable {
        let id: Int
        let app: String
        let bundleId: String
        var title: String
        var workspace: String
        var floating = false
        var fullscreen = false
    }

    private let lock = NSLock()
    private var workspaceNames: [String]
    private var windows: [Window]
    private var focusedId: Int?
    private var focusedName: String
    private var layouts: [String: String] = [:]
    private let knowsRects: Bool
    private var log: [[String]] = []
    private var events: AsyncThrowingStream<String, Error>.Continuation?

    init(_ workspaces: KeyValuePairs<String, [Window]>, focused: Int? = nil, layouts: [String: String] = [:], knowsRects: Bool = false) {
        let all = workspaces.flatMap { name, ws in ws.map { var w = $0; w.workspace = name; return w } }
        workspaceNames = workspaces.map(\.key)
        windows = all
        focusedId = focused
        focusedName = focused.flatMap { id in all.first { $0.id == id }?.workspace } ?? workspaces.first?.key ?? "1"
        self.layouts = layouts
        self.knowsRects = knowsRects
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var focused: Int? { locked { focusedId } }
    var focusedWorkspace: String { locked { focusedName } }
    var workspaces: [String] { locked { workspaceNames } }
    var commands: [[String]] { locked { log } }
    func windows(on workspace: String) -> [Int] { locked { windows.filter { $0.workspace == workspace }.map(\.id) } }
    func layout(of workspace: String) -> String { locked { layouts[workspace] ?? "h_tiles" } }

    func run(_ args: [String]) async throws -> String {
        locked { log.append(args) }
        if !knowsRects, args.contains(where: { $0.contains("window-layout-rect") }) {
            throw AerospaceSocketError.commandFailed(arguments: args, exitCode: 1, stderr: "Can't parse 'window-layout-rect'", serverVersion: nil)
        }
        let (answer, event) = locked { answer(args) }
        if let event { events?.yield(event) }
        return answer
    }

    func userFocus(_ id: Int) { let event = locked { focus(Optional(id)) }; event.map { events?.yield($0) } }

    func userWorkspace(_ name: String) { let event = locked { switchTo(name) }; events?.yield(event) }

    func relayout(_ workspace: String, _ layout: String) { locked { layouts[workspace] = layout } }

    func shift(_ id: Int, to workspace: String) { locked { create(workspace); windows = windows.map { var w = $0; if w.id == id { w.workspace = workspace }; return w } } }

    func remove(_ id: Int) { locked { windows.removeAll { $0.id == id } } }

    func bound(_ command: @escaping @Sendable (FakeAeroSpace) -> Void) {
        events?.yield(#"{"_event":"binding-triggered","binding":"alt-x"}"#)
        Task { try? await Task.sleep(for: .milliseconds(40)); command(self) }
    }

    func announce(_ event: String = "focused-workspace-changed") {
        events?.yield(#"{"_event":"\#(event)","workspace":"\#(focusedWorkspace)"}"#)
    }

    func add(_ window: Window, to workspace: String) {
        locked { create(workspace); var w = window; w.workspace = workspace; windows.append(w) }
        events?.yield(#"{"_event":"window-detected","windowId":\#(window.id),"workspace":"\#(workspace)"}"#)
    }

    func forget(_ workspace: String) {
        locked { workspaceNames.removeAll { $0 == workspace && !windows.contains { $0.workspace == workspace } } }
        events?.yield(#"{"_event":"focused-workspace-changed","workspace":"\#(focusedWorkspace)"}"#)
    }

    func subscribe(_ args: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in self.locked { self.events = continuation; self.log.append(args) } }
    }

    private func answer(_ args: [String]) -> (String, String?) {
        let id = args.firstIndex(of: "--window-id").flatMap { Int(args[$0 + 1]) }
        switch args.first {
        case "list-windows":
            return (json(args.contains("--focused") ? windows.filter { $0.id == focusedId } : ordered), nil)
        case "list-workspaces":
            return ("[" + workspaceNames.map { #"{"workspace":"\#($0)","monitor-id":1,"workspace-root-container-layout":"\#(layouts[$0] ?? "h_tiles")","workspace-is-focused":\#($0 == focusedName)}"# }
                .joined(separator: ",") + "]", nil)
        case "focus":
            return ("", focus(id))
        case "workspace":
            return ("", switchTo(args[1]))
        case "move-node-to-workspace":
            guard let id, let at = windows.firstIndex(where: { $0.id == id }), let name = args.last else { return ("", nil) }
            create(name)
            windows[at].workspace = name
            return ("", args.contains("--focus-follows-window") ? focus(id) : nil)
        case "close":
            windows.removeAll { $0.id == id }
            if focusedId == id { focusedId = windows.last { $0.workspace == focusedName }?.id; return ("", changed()) }
            return ("", nil)
        case "layout":
            let workspace = args.firstIndex(of: "--workspace").map { args[$0 + 1] } ?? focusedName, now = layouts[workspace] ?? "h_tiles"
            layouts[workspace] = args.last == "accordion" ? now.prefix(2) + (now.hasSuffix("tiles") ? "accordion" : "tiles") : args[1]
            return ("", nil)
        default:
            return ("", nil)
        }
    }

    private var ordered: [Window] { workspaceNames.flatMap { name in windows.filter { $0.workspace == name } } }

    private func switchTo(_ name: String) -> String {
        create(name)
        focusedName = name
        focusedId = windows.last { $0.workspace == name }?.id
        return changed()
    }

    private func create(_ name: String) { if !workspaceNames.contains(name) { workspaceNames.append(name) } }

    private func focus(_ id: Int?) -> String? {
        guard let id, let window = windows.first(where: { $0.id == id }) else { return nil }
        (focusedId, focusedName) = (id, window.workspace)
        return changed()
    }

    private func changed() -> String {
        #"{"_event":"focus-changed","windowId":\#(focusedId.map(String.init) ?? "null"),"workspace":"\#(focusedName)"}"#
    }

    private func json(_ list: [Window]) -> String {
        "[" + list.map { w in
            #"{"window-id":\#(w.id),"app-name":"\#(w.app)","app-bundle-id":"\#(w.bundleId)","window-title":"\#(w.title)","#
                + #""workspace":"\#(w.workspace)","window-parent-container-layout":"\#(w.floating ? "floating" : layouts[w.workspace] ?? "h_tiles")","window-is-fullscreen":\#(w.fullscreen)}"#
        }.joined(separator: ",") + "]"
    }
}

func win(_ id: Int, _ app: String, _ title: String = "", floating: Bool = false, fullscreen: Bool = false) -> FakeAeroSpace.Window {
    FakeAeroSpace.Window(id: id, app: app, bundleId: "com." + app.lowercased(), title: title, workspace: "", floating: floating, fullscreen: fullscreen)
}

@MainActor
final class TestApp {
    let store: OverviewStore
    let bridge = FakeBridge()
    private(set) var host: [Visit.Host] = []
    private var pending: Summon?

    init(aerospace: FakeAeroSpace) {
        bridge.granted = true
        store = OverviewStore(runner: aerospace, nativeSystem: bridge)
        store.screen = (available: CGSize(width: 1600, height: 1000), frames: [:], scale: 2)
        store.startListening()
        store.onEffect = { [unowned self] effect in
            self.host.append(effect)
            if case .show(let summon) = effect { self.pending = summon }
            if case .hide = effect { self.store.endVisit() }
        }
    }

    var scene: OverviewScene { store.scene }

    static func onMap(_ aerospace: FakeAeroSpace) async -> TestApp {
        let app = TestApp(aerospace: aerospace)
        await app.open("aerocontrol://workspaces")
        return app
    }

    func open(_ link: String) async {
        store.summon(Summon(URL(string: link)!))
        guard let summon = pending else { return }
        pending = nil
        if await store.open(summon) { await store.capturePreviews() }
    }

    func launchFails(_ ref: AppRef) { store.update { $0.launchFailed(ref) } }

    func mirrors(_ aero: FakeAeroSpace) -> Bool {
        scene.cards.allSatisfy { c in c.tiles.map(\.window.windowId) == aero.windows(on: c.workspace.name) && c.workspace.rootLayout == aero.layout(of: c.workspace.name)
            && c.focused == (c.workspace.name == aero.focusedWorkspace) } && (scene.body != .map || scene.cards.map(\.workspace.name) == aero.workspaces)
    }

    func type(_ text: String) { for c in text { key(.character(c)) } }

    func key(_ key: FilterKey) { store.handle(key) }

    func hover(_ windowId: Int, at point: CGPoint) { store.point(windowId, at: point) }

    func until(_ condition: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async { await waitUntil(condition, sourceLocation: sourceLocation) }

    func past(_ delay: Duration) async { try? await Task.sleep(for: delay + .milliseconds(100)) }
}
