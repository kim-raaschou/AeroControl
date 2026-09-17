import Foundation

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

    /// Also the requested `--format`: `AerospaceCommand` builds the token list from these
    /// keys, so a field can never be asked for under one spelling and decoded under another.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case windowId = "window-id"
        case appName = "app-name"
        case appBundleId = "app-bundle-id"
        case windowTitle = "window-title"
        case workspace
        case parentLayout = "window-parent-container-layout"
    }
}

public struct WorkspaceMonitor: Decodable, Equatable {
    public let workspace: String
    @TolerantInt public var monitorId: Int
    /// Optional so a missing field never fails the whole load: an AeroSpace that does not
    /// emit it just leaves the display unnamed.
    public let monitorName: String?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case workspace
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
    }

    public init(workspace: String, monitorId: Int, monitorName: String? = nil) {
        self.workspace = workspace
        self.monitorId = monitorId
        self.monitorName = monitorName
    }
}

public struct ParsedWindow: Equatable {
    public let window: WindowInfo
    public let workspace: String

    public init(window: WindowInfo, workspace: String) {
        self.window = window
        self.workspace = workspace
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
                title: dw.windowTitle ?? ""
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
            windows: byWorkspace[wm.workspace]?.map(\.window) ?? [],
            monitorId: wm.monitorId,
            monitorName: wm.monitorName ?? ""
        )
    }

    return OverviewResult(workspaces: workspaces, focus: focus)
}

/// Focus from the two `--focused` reads. `nil` when neither answered, so a load during an
/// AeroSpace restart leaves the focus ring alone instead of clearing it on every reload.
public func parseFocus(windowJson: String?, workspaceJson: String?) -> Focus? {
    guard windowJson != nil || workspaceJson != nil else { return nil }
    let windowId = (try? parseWindows(json: windowJson ?? ""))?.first?.window.windowId ?? 0
    let workspace = (try? parseWorkspaces(json: workspaceJson ?? ""))?.first?.workspace ?? ""
    return Focus(windowId: windowId, workspace: workspace)
}

/// Reads AeroSpace's whole state. The reads are **sequential on purpose**: AeroSpace
/// serialises command execution, so two different commands issued concurrently contend and
/// cost more than twice their sequential total — measured 12.8 ms concurrent against 6.4 ms
/// sequential for the two list reads on this machine. Do not reintroduce `async let` here.
///
/// A read issued in reaction to an AeroSpace event cannot see stale state: the daemon
/// queues it behind its own work, so there is no read-too-early race to guard against.
public func loadOverview(using runner: AerospaceProcessRunner) async throws -> OverviewResult {
    let windows = try parseWindows(json: try await runner.run(AerospaceCommand.listWindows()))
    let workspaceMonitors = try parseWorkspaces(json: try await runner.run(AerospaceCommand.listWorkspaces()))
    // Tolerant: the lists are the load, focus is a refinement of it.
    let focusedWindow = try? await runner.run(AerospaceCommand.listFocusedWindow())
    let focusedWorkspace = try? await runner.run(AerospaceCommand.listFocusedWorkspace())
    let focus = parseFocus(windowJson: focusedWindow, workspaceJson: focusedWorkspace)
    return buildOverviewResult(windows: windows, workspaceMonitors: workspaceMonitors, focus: focus)
}
