import Foundation

extension AerospaceEvent {
    /// The names that mean "AeroSpace changed, read it again".
    private static let readAgain: Set<String> = ["focused-workspace-changed", "focused-monitor-changed", "window-detected", "binding-triggered"]

    public static func parse(_ json: String) -> AerospaceEvent? {
        guard let raw = try? JSONDecoder().decode(RawEvent.self, from: Data(json.utf8)) else {
            return nil
        }
        if raw.event == "focus-changed" { return .focusChanged(windowId: raw.windowId, workspace: raw.workspace ?? "") }
        return readAgain.contains(raw.event) ? .changed : nil
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
