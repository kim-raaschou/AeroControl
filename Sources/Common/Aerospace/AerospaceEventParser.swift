import Foundation

/// Single source of truth for the AeroSpace CLI's `_event` names — a faithful mirror
/// of the events **stock** AeroSpace emits. Not every name is acted on: ones that can't
/// change the window/workspace layout (e.g. `mode-changed`) are recognised here but fall
/// through to `.other` in the parser. Deliberately absent: any "window-closed" — stock
/// AeroSpace emits no close event, so AeroControl emulates that itself locally
/// (`AerospaceEvent.localWindowClosed`) rather than depending on it arriving on the stream.
/// The b-event-name-pin test locks these against AeroSpace's set.
public enum AerospaceEventName: String, CaseIterable {
    case focusChanged = "focus-changed"
    case workspaceChanged = "focused-workspace-changed"
    case monitorChanged = "focused-monitor-changed"
    case modeChanged = "mode-changed"
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
        case .modeChanged, nil:
            // Recognised but intentionally not acted on: `mode-changed` can't alter the
            // window/workspace layout. Any unknown/future name lands here too. Both fall
            // through to a no-op so AeroControl only reconciles on layout-affecting events.
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
