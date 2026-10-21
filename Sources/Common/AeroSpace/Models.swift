import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public let windowId: Int
    let appName: String
    public let bundleId: String
    public let isFloating: Bool
    let isFullscreen: Bool
    public let isHidden: Bool
    public let title: String
    let layoutRect: CGRect?
    public let workspace: String

    public init(windowId: Int, appName: String, bundleId: String, isFloating: Bool = false,
                isFullscreen: Bool = false, isHidden: Bool = false, title: String = "", layoutRect: CGRect? = nil, workspace: String = "") {
        self.windowId = windowId
        self.appName = appName
        self.bundleId = bundleId
        self.isFloating = isFloating
        self.isFullscreen = isFullscreen
        self.isHidden = isHidden
        self.layoutRect = layoutRect
        self.title = title
        self.workspace = workspace
    }

    var isTiled: Bool { !isFloating && !isFullscreen && !isHidden }

    public var caption: String {
        let text = title.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return appName }
        for separator in [" — ", " – ", " - ", " | "] {
            let tail = separator + appName
            if text.count > tail.count, text.suffix(tail.count).lowercased() == tail.lowercased() {
                let head = text.dropLast(tail.count).trimmingCharacters(in: .whitespaces)
                return head.isEmpty ? appName : head
            }
        }
        return text
    }
}

public struct WorkspaceInfo: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let windows: [WindowInfo]
    let monitorId: Int
    public let monitorName: String
    let screenIndex: Int
    public let rootLayout: String
    public let isVisible: Bool

    var standIn: Int {
        -1 - Int(name.utf8.reduce(UInt32(2_166_136_261)) { ($0 ^ UInt32($1)) &* 16_777_619 } >> 1)
    }

    var monitorShortName: String? {
        monitorName.split(separator: " ").first.map(String.init)
    }

    public init(name: String, windows: [WindowInfo], monitorId: Int = 1, monitorName: String = "", screenIndex: Int = 0, rootLayout: String = "", isVisible: Bool = false) {
        self.name = name
        self.windows = windows
        self.monitorId = monitorId
        self.monitorName = monitorName
        self.screenIndex = screenIndex
        self.rootLayout = rootLayout
        self.isVisible = isVisible
    }

    public func with(windows: [WindowInfo]) -> WorkspaceInfo {
        WorkspaceInfo(name: name, windows: windows, monitorId: monitorId, monitorName: monitorName, screenIndex: screenIndex, rootLayout: rootLayout, isVisible: isVisible)
    }
}
