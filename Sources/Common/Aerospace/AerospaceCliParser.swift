import Foundation

// MARK: - Tolerant decoding

/// Decodes an integer field tolerantly. AeroSpace's `%{monitor-id}` and
/// `%{monitor-appkit-nsscreen-screens-id}` tokens fall back to the string sentinels
/// `"NULL-MONITOR"` / `"NULL-MONITOR-ID"` when a window has no managed monitor (e.g.
/// unmanaged popups) or a monitor lacks a 1-based index. A strict `Int` decode would
/// throw `typeMismatch` and fail the entire array decode, blanking the HUD. Fall back
/// to `0`. Value sentinels can appear regardless of AeroSpace version, so this stays
/// even though the app pins a minimum version and always requests the field.
@propertyWrapper
public struct TolerantInt: Decodable, Equatable {
    public var wrappedValue: Int
    public init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Int.self) { wrappedValue = value }
        else if let string = try? c.decode(String.self), let value = Int(string) { wrappedValue = value }
        else { wrappedValue = 0 }
    }
}

extension KeyedDecodingContainer {
    /// Missing-key tolerance for `@TolerantInt`: an absent key yields `0`.
    func decode(_ type: TolerantInt.Type, forKey key: Key) throws -> TolerantInt {
        try decodeIfPresent(type, forKey: key) ?? TolerantInt(wrappedValue: 0)
    }
}

// MARK: - Decoded types from aerospace CLI JSON output

public struct DecodedWindow: Decodable, Equatable {
    public let windowId: Int
    public let appName: String
    public let appBundleId: String
    public let workspace: String
    // Required: AeroSpace ≥ the pinned minimum always emits a parent-container layout
    // for every window, and the app explicitly requests the field.
    public let parentLayout: String
    @TolerantInt public var monitorId: Int

    // Local keys (auto-synthesis rejects a shared key enum with extra cases). The
    // b-drift-guard test enforces that these stay in lockstep with the field tokens
    // AerospaceCommand.listWindows() requests, so a drift can't silently blank the HUD.
    private enum CodingKeys: String, CodingKey {
        case windowId = "window-id"
        case appName = "app-name"
        case appBundleId = "app-bundle-id"
        case workspace
        case parentLayout = "window-parent-container-layout"
        case monitorId = "monitor-id"
    }
}

public struct WorkspaceMonitor: Decodable, Equatable {
    public let workspace: String
    @TolerantInt public var monitorId: Int

    private enum CodingKeys: String, CodingKey {
        case workspace
        case monitorId = "monitor-id"
    }

    public init(workspace: String, monitorId: Int) {
        self.workspace = workspace
        self.monitorId = monitorId
    }
}

public struct ParsedWindow: Equatable {
    public let window: WindowInfo
    public let workspace: String
    public let monitorId: Int

    public init(window: WindowInfo, workspace: String, monitorId: Int) {
        self.window = window
        self.workspace = workspace
        self.monitorId = monitorId
    }
}

// MARK: - Parsing functions

public func parseWindows(json: String) throws -> [ParsedWindow] {
    guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
    let decoded = try JSONDecoder().decode([DecodedWindow].self, from: data)
    return decoded.map { dw in
        ParsedWindow(
            window: WindowInfo(
                windowId: dw.windowId,
                appName: dw.appName,
                bundleId: dw.appBundleId,
                isFloating: dw.parentLayout == "floating"
            ),
            workspace: dw.workspace,
            monitorId: dw.monitorId
        )
    }
}

public func parseWorkspaces(json: String) throws -> [WorkspaceMonitor] {
    guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
    return try JSONDecoder().decode([WorkspaceMonitor].self, from: data)
}

public func buildOverviewResult(windows: [ParsedWindow], workspaceMonitors: [WorkspaceMonitor]) -> OverviewResult {
    let byWorkspace = Dictionary(grouping: windows, by: \.workspace)

    let workspaces = workspaceMonitors.map { wm in
        WorkspaceInfo(
            name: wm.workspace,
            windows: byWorkspace[wm.workspace]?.map(\.window) ?? [],
            monitorId: wm.monitorId
        )
    }

    return OverviewResult(workspaces: workspaces)
}

/// Orchestrates the list commands and parsing into a complete overview.
/// Effectful only through the injected runner port — deterministic given its outputs.
public func loadOverview(using runner: AerospaceProcessRunner) async throws -> OverviewResult {
    async let windowsJson = runner.run(AerospaceCommand.listWindows())
    async let workspacesJson = runner.run(AerospaceCommand.listWorkspaces())
    let windows = try parseWindows(json: try await windowsJson)
    let workspaceMonitors = try parseWorkspaces(json: try await workspacesJson)
    return buildOverviewResult(windows: windows, workspaceMonitors: workspaceMonitors)
}
