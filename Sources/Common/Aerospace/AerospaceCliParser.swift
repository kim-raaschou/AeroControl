import Foundation

@propertyWrapper
public struct TolerantInt: Decodable, Equatable {
    public var wrappedValue: Int
    public init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        wrappedValue = (try? c.decode(Int.self)) ?? (try? c.decode(String.self)).flatMap { Int($0) } ?? 0
    }
}

extension KeyedDecodingContainer {
    func decode(_ type: TolerantInt.Type, forKey key: Key) throws -> TolerantInt {
        try decodeIfPresent(type, forKey: key) ?? TolerantInt(wrappedValue: 0)
    }
}

public struct DecodedWindow: Decodable, Equatable {
    public let windowId: Int
    public let appName: String
    public let appBundleId: String
    public var windowTitle: String?
    public let workspace: String
    public let parentLayout: String
    /// Optional so a list from an AeroSpace without the field still decodes.
    public let windowIsFullscreen: Bool?
    /// `x,y,width,height`; only asked for from an AeroSpace that knows it, empty for a float.
    public let windowLayoutRect: String?

    /// Also the requested `--format`: `AerospaceCommand` builds the token list from these
    /// keys, so a field can never be asked for under one spelling and decoded under another.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case windowId = "window-id"
        case appName = "app-name"
        case appBundleId = "app-bundle-id"
        case windowTitle = "window-title"
        case workspace
        case parentLayout = "window-parent-container-layout"
        case windowIsFullscreen = "window-is-fullscreen"
        case windowLayoutRect = "window-layout-rect"
    }
}

/// `x,y,width,height` in points to a rect; nil for anything else, an empty string included.
public func parseLayoutRect(_ text: String?) -> CGRect? {
    let parts = (text ?? "").split(separator: ",").compactMap { Double($0) }
    return parts.count == 4 ? CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) : nil
}

public struct WorkspaceMonitor: Decodable, Equatable {
    public let workspace: String
    @TolerantInt public var monitorId: Int
    /// Optional so a missing field never fails the whole load: an AeroSpace that does not
    /// emit it just leaves the display unnamed.
    public let monitorName: String?
    /// 1-based into `NSScreen.screens`; 0 when absent.
    @TolerantInt public var screenIndex: Int
    /// How the workspace's root container is laid out: `h_tiles`, `v_tiles`, `h_accordion`,
    /// `v_accordion`. Optional for the same reason: an older AeroSpace leaves it out.
    public let rootLayout: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case workspace
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
        case screenIndex = "monitor-appkit-nsscreen-screens-id"
        case rootLayout = "workspace-root-container-layout"
    }

    public init(workspace: String, monitorId: Int, monitorName: String? = nil, screenIndex: Int = 0, rootLayout: String? = nil) {
        self.workspace = workspace
        self.monitorId = monitorId
        self.monitorName = monitorName
        self.screenIndex = screenIndex
        self.rootLayout = rootLayout
    }
}

public func parseWindows(json: String) throws -> [ParsedWindow] {
    guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
    let decoded = try JSONDecoder().decode([DecodedWindow].self, from: data)
    return decoded.map { dw in
        ParsedWindow(
            window: WindowInfo(
                windowId: dw.windowId,
                appName: dw.appName,
                bundleId: dw.appBundleId,
                // What AeroSpace says of the window's place: floating, or one of macOS's own states.
                isFloating: dw.parentLayout == "floating",
                isFullscreen: dw.windowIsFullscreen ?? false || dw.parentLayout == "macos_native_fullscreen",
                isHidden: ["macos_native_minimized", "macos_native_window_of_hidden_app"].contains(dw.parentLayout),
                title: dw.windowTitle ?? "",
                layoutRect: parseLayoutRect(dw.windowLayoutRect)
            ),
            workspace: dw.workspace
        )
    }
}

public func parseWorkspaces(json: String) throws -> [WorkspaceMonitor] {
    guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
    return try JSONDecoder().decode([WorkspaceMonitor].self, from: data)
}

public func buildOverviewResult(windows: [ParsedWindow], workspaceMonitors: [WorkspaceMonitor],
                                focus: Focus? = nil) -> OverviewResult {
    let byWorkspace = Dictionary(grouping: windows, by: \.workspace)

    let workspaces = workspaceMonitors.map { wm in
        WorkspaceInfo(
            name: wm.workspace,
            windows: layoutOrdered(byWorkspace[wm.workspace]?.map(\.window) ?? []),
            monitorId: wm.monitorId,
            monitorName: wm.monitorName ?? "",
            screenIndex: wm.screenIndex,
            rootLayout: wm.rootLayout ?? ""
        )
    }

    return OverviewResult(workspaces: workspaces, focus: focus)
}

/// A workspace's windows in the layout's order when AeroSpace said where each tiled one is
/// (`WorkspaceTree.order`), so the ring, the keys and the strip follow what the eye sees, not
/// AeroSpace's listing by app name; windows without a rect — floats, a fullscreen window in
/// front — come after them in the listing's order. Without rects the listing's order stands.
func layoutOrdered(_ windows: [WindowInfo]) -> [WindowInfo] {
    let placed = windows.compactMap { w in w.layoutRect.map { (w.windowId, $0) } }
    guard placed.count > 1 else { return windows }
    let rank = Dictionary(uniqueKeysWithValues: WorkspaceTree.order(placed).enumerated().map { ($1, $0) })
    return windows.enumerated().sorted { a, b in
        (rank[a.element.windowId] ?? placed.count + a.offset, a.offset) < (rank[b.element.windowId] ?? placed.count + b.offset, b.offset)
    }.map(\.element)
}

/// Focus from the two `--focused` reads. `nil` when neither answered, so a load during an
/// AeroSpace restart leaves the focus ring alone instead of clearing it on every reload.
public func parseFocus(windowJson: String?, workspaceJson: String?) -> Focus? {
    guard windowJson != nil || workspaceJson != nil else { return nil }
    let windowId = (try? parseWindows(json: windowJson ?? ""))?.first?.window.windowId ?? 0
    let workspace = (try? parseWorkspaces(json: workspaceJson ?? ""))?.first?.workspace ?? ""
    return Focus(windowId: windowId, workspace: workspace)
}

/// The window AeroSpace has focused, read when asked: for the menu, and for the check that a
/// focus took. Nil with nothing focused, or when AeroSpace does not answer.
public func loadFocusedWindow(using runner: AerospaceProcessRunner) async -> WindowInfo? {
    (try? await runner.run(AerospaceCommand.listFocusedWindow)).flatMap { try? parseWindows(json: $0).first?.window }
}

/// Reads AeroSpace's whole state. The reads are **sequential on purpose**: AeroSpace
/// serialises command execution, so two different commands issued concurrently contend and
/// cost more than twice their sequential total — measured 12.8 ms concurrent against 6.4 ms
/// sequential for the two list reads on this machine. Do not reintroduce `async let` here.
///
/// A read issued in reaction to an AeroSpace event cannot see stale state: the daemon
/// queues it behind its own work, so there is no read-too-early race to guard against.
///
/// Every load asks for `%{window-layout-rect}` (the owner's AeroSpace branch). A release AeroSpace
/// answers that it cannot parse the variable, and the plain read follows in the same load: one
/// failed call, about 2 ms, per load, and nothing remembered that could drift when the AeroSpace
/// is swapped. Any other failure is a failure.
public func loadOverview(using runner: AerospaceProcessRunner) async throws -> OverviewResult {
    let windowsJson: String
    do {
        windowsJson = try await runner.run(AerospaceCommand.listWindows(layoutRects: true))
    } catch {
        guard "\(error)".contains("window-layout-rect") else { throw error }
        windowsJson = try await runner.run(AerospaceCommand.listWindows())
    }
    let windows = try parseWindows(json: windowsJson)
    let workspaceMonitors = try parseWorkspaces(json: try await runner.run(AerospaceCommand.listWorkspaces))
    // Tolerant: the lists are the load, focus is a refinement of it.
    let focusedWindow = try? await runner.run(AerospaceCommand.listFocusedWindow)
    let focusedWorkspace = try? await runner.run(AerospaceCommand.listFocusedWorkspace)
    let focus = parseFocus(windowJson: focusedWindow, workspaceJson: focusedWorkspace)
    return buildOverviewResult(windows: windows, workspaceMonitors: workspaceMonitors, focus: focus)
}
