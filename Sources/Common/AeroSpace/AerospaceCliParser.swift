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
    public let windowIsFullscreen: Bool?
    public let windowLayoutRect: String?

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

public func parseLayoutRect(_ text: String?) -> CGRect? {
    let parts = (text ?? "").split(separator: ",").compactMap { Double($0) }
    return parts.count == 4 ? CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) : nil
}

public struct WorkspaceMonitor: Decodable, Equatable {
    public let workspace: String
    @TolerantInt public var monitorId: Int
    public let monitorName: String?
    @TolerantInt public var screenIndex: Int
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

func layoutOrdered(_ windows: [WindowInfo]) -> [WindowInfo] {
    let placed = windows.compactMap { w in w.layoutRect.map { (w.windowId, $0) } }
    guard placed.count > 1 else { return windows }
    let rank = Dictionary(uniqueKeysWithValues: WorkspaceTree.order(placed).enumerated().map { ($1, $0) })
    return windows.enumerated().sorted { a, b in
        (rank[a.element.windowId] ?? placed.count + a.offset, a.offset) < (rank[b.element.windowId] ?? placed.count + b.offset, b.offset)
    }.map(\.element)
}

public func parseFocus(windowJson: String?, workspaceJson: String?) -> Focus? {
    guard windowJson != nil || workspaceJson != nil else { return nil }
    let windowId = (try? parseWindows(json: windowJson ?? ""))?.first?.window.windowId ?? 0
    let workspace = (try? parseWorkspaces(json: workspaceJson ?? ""))?.first?.workspace ?? ""
    return Focus(windowId: windowId, workspace: workspace)
}

public func loadFocusedWindow(using runner: AerospaceProcessRunner) async -> WindowInfo? {
    (try? await runner.run(AerospaceCommand.listFocusedWindow)).flatMap { try? parseWindows(json: $0).first?.window }
}

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
    let focusedWindow = try? await runner.run(AerospaceCommand.listFocusedWindow)
    let focusedWorkspace = try? await runner.run(AerospaceCommand.listFocusedWorkspace)
    let focus = parseFocus(windowJson: focusedWindow, workspaceJson: focusedWorkspace)
    return buildOverviewResult(windows: windows, workspaceMonitors: workspaceMonitors, focus: focus)
}
