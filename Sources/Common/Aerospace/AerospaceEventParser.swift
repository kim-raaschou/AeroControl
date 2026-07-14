import Foundation

/// Single source of truth for the AeroSpace CLI's `_event` names. Kept next to the
/// parser so the strings AeroSpace emits live in exactly one place; the
/// b-event-name-pin test locks these against the cases the parser handles.
public enum AerospaceEventName: String, CaseIterable {
    case focusChanged = "focus-changed"
    case workspaceChanged = "focused-workspace-changed"
    case monitorChanged = "focused-monitor-changed"
    case windowDetected = "window-detected"
    case bindingTriggered = "binding-triggered"
}

/// Transport: parses the AeroSpace CLI's JSON event stream into domain `AerospaceEvent` values.
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
            // A window-detected event with no id is unusable — routing it as `.other`
            // avoids fabricating windowId 0, which collides with the "no focused window"
            // sentinel and would inject a phantom tile.
            guard let windowId = raw.windowId else { return .other }
            return .windowDetected(
                windowId: windowId,
                workspace: raw.workspace,
                appBundleId: raw.appBundleId,
                appName: raw.appName
            )
        case .bindingTriggered:
            return .bindingTriggered
        case nil:
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
