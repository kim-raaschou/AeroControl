import Foundation

public enum AerospaceEventName: String, CaseIterable {
    case focusChanged = "focus-changed"
    case workspaceChanged = "focused-workspace-changed"
    case monitorChanged = "focused-monitor-changed"
    case modeChanged = "mode-changed"
    case windowDetected = "window-detected"
    case bindingTriggered = "binding-triggered"
}

extension AerospaceEvent {
    public static func parse(_ json: String) -> AerospaceEvent? {
        guard let raw = try? JSONDecoder().decode(RawEvent.self, from: Data(json.utf8)) else {
            return nil
        }

        switch AerospaceEventName(rawValue: raw.event) {
        case .focusChanged:
            return .focusChanged(windowId: raw.windowId, workspace: raw.workspace ?? "")
        case .workspaceChanged:
            return .workspaceChanged(workspace: raw.workspace ?? "", prevWorkspace: raw.prevWorkspace ?? "")
        case .monitorChanged:
            return .monitorChanged(workspace: raw.workspace ?? "", monitorId: raw.monitorId)
        case .windowDetected:
            guard let windowId = raw.windowId else { return .other }
            return .windowDetected(
                windowId: windowId,
                workspace: raw.workspace,
                appBundleId: raw.appBundleId,
                appName: raw.appName
            )
        case .bindingTriggered:
            return .bindingTriggered
        case .modeChanged, nil:
            return .other
        }
    }

    private struct RawEvent: Decodable {
        let event: String
        let windowId: Int?
        let workspace: String?
        let prevWorkspace: String?
        let appBundleId: String?
        let appName: String?
        let monitorId: Int?

        private enum CodingKeys: String, CodingKey {
            case event = "_event"
            case windowId, workspace, prevWorkspace, appBundleId, appName, monitorId
        }
    }
}
