import Foundation

extension AerospaceEvent {
    /// The names that mean "AeroSpace changed, read it again". `mode-changed` is deliberately
    /// absent: it moves no window, so it falls through to `.other` like any future name we do
    /// not know. A focus change is read whole; of every other line only the name.
    private static let readAgain: Set<String> = ["focused-workspace-changed", "focused-monitor-changed", "window-detected", "binding-triggered"]

    public static func parse(_ json: String) -> AerospaceEvent? {
        guard let raw = try? JSONDecoder().decode(RawEvent.self, from: Data(json.utf8)) else {
            return nil
        }
        if raw.event == "focus-changed" { return .focusChanged(windowId: raw.windowId, workspace: raw.workspace ?? "") }
        return readAgain.contains(raw.event) ? .changed : .other
    }

    private struct RawEvent: Decodable {
        let event: String
        let windowId: Int?
        let workspace: String?

        private enum CodingKeys: String, CodingKey {
            case event = "_event"
            case windowId, workspace
        }
    }
}
