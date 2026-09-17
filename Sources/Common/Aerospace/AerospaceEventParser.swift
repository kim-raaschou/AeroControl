import Foundation

/// The event names that mean "AeroSpace changed, read it again". `mode-changed` is
/// deliberately absent: it moves no window, so it falls through to `.other` like any
/// future name we do not know.
public enum AerospaceEventName: String, CaseIterable {
    case focusChanged = "focus-changed"
    case workspaceChanged = "focused-workspace-changed"
    case monitorChanged = "focused-monitor-changed"
    case windowDetected = "window-detected"
    case bindingTriggered = "binding-triggered"
}

extension AerospaceEvent {
    /// Only the name is read. The rest of the line is AeroSpace's business.
    public static func parse(_ json: String) -> AerospaceEvent? {
        guard let raw = try? JSONDecoder().decode(RawEvent.self, from: Data(json.utf8)) else {
            return nil
        }
        return AerospaceEventName(rawValue: raw.event) == nil ? .other : .changed
    }

    private struct RawEvent: Decodable {
        let event: String

        private enum CodingKeys: String, CodingKey {
            case event = "_event"
        }
    }
}
