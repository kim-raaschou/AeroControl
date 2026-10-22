import Foundation
import CoreGraphics

@propertyWrapper
struct TolerantInt: Decodable, Equatable {
    var wrappedValue: Int
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

struct DecodedWindow: Decodable, Equatable {
    public let windowId: Int
    let appName: String
    let appBundleId: String
    var windowTitle: String?
    public let workspace: String
    let parentLayout: String
    let windowIsFullscreen: Bool?
    let windowLayoutRect: String?

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

func parseLayoutRect(_ text: String?) -> CGRect? {
    let parts = (text ?? "").split(separator: ",").compactMap { Double($0) }
    return parts.count == 4 ? CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3]) : nil
}

struct WorkspaceMonitor: Decodable, Equatable {
    public let workspace: String
    @TolerantInt public var monitorId: Int
    public let monitorName: String?
    @TolerantInt public var screenIndex: Int
    public let rootLayout: String?
    public let isFocused: Bool?
    public let isVisible: Bool?

    enum CodingKeys: String, CodingKey, CaseIterable {
        case workspace
        case monitorId = "monitor-id"
        case monitorName = "monitor-name"
        case screenIndex = "monitor-appkit-nsscreen-screens-id"
        case rootLayout = "workspace-root-container-layout"
        case isFocused = "workspace-is-focused"
        case isVisible = "workspace-is-visible"
    }
}

func parseWindows(json: String) throws -> [WindowInfo] {
    guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
    let decoded = try JSONDecoder().decode([DecodedWindow].self, from: data)
    return decoded.map { dw in
        WindowInfo(
            windowId: dw.windowId,
            appName: dw.appName,
            bundleId: dw.appBundleId,
            isFloating: dw.parentLayout == "floating",
            isFullscreen: dw.windowIsFullscreen ?? false || dw.parentLayout == "macos_native_fullscreen",
            isHidden: ["macos_native_minimized", "macos_native_window_of_hidden_app"].contains(dw.parentLayout),
            title: dw.windowTitle ?? "",
            layoutRect: parseLayoutRect(dw.windowLayoutRect),
            workspace: dw.workspace
        )
    }
}

func parseWorkspaces(json: String) throws -> [WorkspaceMonitor] {
    guard let data = json.data(using: .utf8), !json.isEmpty else { return [] }
    return try JSONDecoder().decode([WorkspaceMonitor].self, from: data)
}

func buildOverview(windows: [WindowInfo], workspaceMonitors: [WorkspaceMonitor], focusedWindowId: Int = 0) -> OverviewModel {
    let byWorkspace = Dictionary(grouping: windows, by: \.workspace)

    let workspaces = workspaceMonitors.map { wm in
        WorkspaceInfo(
            name: wm.workspace,
            windows: layoutOrdered(byWorkspace[wm.workspace] ?? []),
            monitorId: wm.monitorId,
            monitorName: wm.monitorName ?? "",
            screenIndex: wm.screenIndex,
            rootLayout: wm.rootLayout ?? "",
            isVisible: wm.isVisible ?? false
        )
    }

    return OverviewModel(workspaces: workspaces, focusedWindowId: focusedWindowId, focusedWorkspace: workspaceMonitors.first { $0.isFocused == true }?.workspace ?? "")
}

func layoutOrdered(_ windows: [WindowInfo]) -> [WindowInfo] {
    let placed = windows.filter(\.isTiled).compactMap { w in w.layoutRect.map { (w.windowId, $0) } }
    guard placed.count > 1 else { return windows }
    let rank = Dictionary(uniqueKeysWithValues: WorkspaceTree.order(placed).enumerated().map { ($1, $0) })
    return windows.enumerated().sorted { a, b in
        (rank[a.element.windowId] ?? placed.count + a.offset, a.offset) < (rank[b.element.windowId] ?? placed.count + b.offset, b.offset)
    }.map(\.element)
}

func loadFocusedWindow(using runner: AerospaceProcessRunner) async -> WindowInfo? {
    (try? await runner.run(AerospaceCommand.listFocusedWindow)).flatMap { try? parseWindows(json: $0).first }
}

public func loadOverview(using runner: AerospaceProcessRunner) async throws -> OverviewModel {
    let windowsJson: String
    do {
        windowsJson = try await runner.run(AerospaceCommand.listWindows(layoutRects: true))
    } catch {
        guard "\(error)".contains("window-layout-rect") else { throw error }
        windowsJson = try await runner.run(AerospaceCommand.listWindows())
    }
    let windows = try parseWindows(json: windowsJson)
    let workspaceMonitors = try parseWorkspaces(json: try await runner.run(AerospaceCommand.listWorkspaces))
    let focused = await loadFocusedWindow(using: runner)?.windowId ?? 0
    return buildOverview(windows: windows, workspaceMonitors: workspaceMonitors, focusedWindowId: focused)
}

enum WorkspaceTree {
    static func order(_ rects: [(Int, CGRect)]) -> [Int] { balanced(rects, in: .zero, gap: 0).map(\.0) }

    static func balanced(_ rects: [(Int, CGRect)], in box: CGRect, gap: CGFloat) -> [(Int, CGRect)] {
        let axes = [(\CGRect.minX, \CGRect.maxX, \CGSize.width, CGRectEdge.minXEdge), (\.minY, \.maxY, \.height, .minYEdge)]
        guard rects.count > 1, let split = axes.lazy.compactMap({ lo, hi, side, edge in cut(rects, lo, hi).map { (parts: $0, side: side, edge: edge) } }).first else { return rects.map { ($0.0, box) } }
        let n = CGFloat(split.parts.count), span = box.size[keyPath: split.side] + gap, at = (0...split.parts.count).map { (span * CGFloat($0) / n).rounded() }
        return split.parts.enumerated().flatMap { i, part in balanced(part, in: box.divided(atDistance: at[i + 1] - gap, from: split.edge).slice.divided(atDistance: at[i], from: split.edge).remainder, gap: gap) }
    }

    private static func cut(_ rects: [(Int, CGRect)], _ lo: KeyPath<CGRect, CGFloat>, _ hi: KeyPath<CGRect, CGFloat>) -> [[(Int, CGRect)]]? {
        let indexed = rects.enumerated().sorted { $0.element.1[keyPath: lo] < $1.element.1[keyPath: lo] }
        var runs: [[(offset: Int, element: (Int, CGRect))]] = [[indexed[0]]]
        var end = indexed[0].element.1[keyPath: hi]
        for item in indexed.dropFirst() {
            if item.element.1[keyPath: lo] >= end - 2 { runs.append([item]) } else { runs[runs.count - 1].append(item) }
            end = max(end, item.element.1[keyPath: hi])
        }
        guard runs.count > 1 else { return nil }
        return runs.map { run in run.sorted { $0.offset < $1.offset }.map(\.element) }
    }
}
