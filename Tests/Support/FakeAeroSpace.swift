import Foundation
@testable import AeroControlKit
@testable import Common

final class FakeAeroSpace: AerospaceProcessRunner, @unchecked Sendable {
    struct Window: Equatable {
        let id: Int
        let app: String
        let bundleId: String
        var title: String
        var workspace: String
        var floating = false
    }

    private let lock = NSLock()
    private var workspaceNames: [String]
    private var windows: [Window]
    private var focusedId: Int?
    private var focusedName: String
    private var layouts: [String: String] = [:]
    private var log: [[String]] = []
    private var events: AsyncThrowingStream<String, Error>.Continuation?

    init(_ workspaces: KeyValuePairs<String, [Window]>, focused: Int? = nil, layouts: [String: String] = [:]) {
        let all = workspaces.flatMap { name, ws in ws.map { var w = $0; w.workspace = name; return w } }
        workspaceNames = workspaces.map(\.key)
        windows = all
        focusedId = focused
        focusedName = focused.flatMap { id in all.first { $0.id == id }?.workspace } ?? workspaces.first?.key ?? "1"
        self.layouts = layouts
    }

    private func locked<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }

    var focused: Int? { locked { focusedId } }
    var focusedWorkspace: String { locked { focusedName } }
    var commands: [[String]] { locked { log } }
    func windows(on workspace: String) -> [Int] { locked { windows.filter { $0.workspace == workspace }.map(\.id) } }
    func layout(of workspace: String) -> String { locked { layouts[workspace] ?? "h_tiles" } }

    func run(_ args: [String]) async throws -> String {
        if args.contains(where: { $0.contains("window-layout-rect") }) {
            throw AerospaceSocketError.commandFailed(arguments: args, exitCode: 1, stderr: "Can't parse 'window-layout-rect'", serverVersion: nil)
        }
        let (answer, event) = locked { () -> (String, String?) in
            log.append(args)
            return answer(args)
        }
        if let event { events?.yield(event) }
        return answer
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
            let names = args.contains("--focused") ? [focusedName] : workspaceNames
            return ("[" + names.map { #"{"workspace":"\#($0)","monitor-id":1,"workspace-root-container-layout":"\#(layouts[$0] ?? "h_tiles")"}"# }
                .joined(separator: ",") + "]", nil)
        case "focus":
            return ("", focus(id))
        case "workspace":
            let name = args[1]
            create(name)
            focusedName = name
            focusedId = windows.last { $0.workspace == name }?.id
            return ("", changed())
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
            layouts[focusedName] = args[1]
            return ("", nil)
        default:
            return ("", nil)
        }
    }

    private var ordered: [Window] { workspaceNames.flatMap { name in windows.filter { $0.workspace == name } } }

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
                + #""workspace":"\#(w.workspace)","window-parent-container-layout":"\#(w.floating ? "floating" : layouts[w.workspace] ?? "h_tiles")"}"#
        }.joined(separator: ",") + "]"
    }
}

func win(_ id: Int, _ app: String, _ title: String = "", floating: Bool = false) -> FakeAeroSpace.Window {
    FakeAeroSpace.Window(id: id, app: app, bundleId: "com." + app.lowercased(), title: title, workspace: "", floating: floating)
}

@MainActor
final class TestApp {
    let store: OverviewStore

    init(aerospace: FakeAeroSpace) {
        store = OverviewStore(runner: aerospace, nativeSystem: FakeBridge())
        store.screen = (available: CGSize(width: 1600, height: 1000), frames: [:])
        store.startListening()
    }

    var scene: OverviewScene { store.scene }

    func open(_ link: String) async {
        await store.reload()
        if case .app(let ref) = Summon(URL(string: link)!), case .focus(let id) = store.summonApp(ref) { store.send(.action(.focusWindow(id))) }
        store.following = true
    }

    func type(_ text: String) { for c in text { key(.character(c)) } }

    func key(_ key: FilterKey) {
        if case .focus(let id) = store.handle(key) { store.send(.action(.focusWindow(id))) }
    }

    func closeRinged() { if let target = store.commandTarget { store.send(.action(.closeWindow(target.windowId))) } }

    func settled() async { try? await Task.sleep(for: .milliseconds(150)) }
}
