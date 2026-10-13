import Foundation

public enum KeyHelp {
    public struct Row: Equatable, Sendable {
        public let keys: String
        public let does: String
    }

    public static let map: [Row] = [
        Row(keys: "letters, digits, space", does: "filter; the grid narrows from the second character"),
        Row(keys: "← → ↑ ↓", does: "move the ring through the windows as drawn, on to the next workspace, AeroSpace's focus going along; an empty one is a stop"),
        Row(keys: "⌘← ⌘→", does: "the previous / next workspace's first window, or the empty workspace itself"),
        Row(keys: "⌘↑ ⌘↓", does: "the first window of the workspace above / below"),
        Row(keys: "⇧⌘ + a key", does: "move the window under the ring to the workspace of that name; a new name creates it"),
        Row(keys: "⌘W", does: "close the window under the ring; the overview stays up"),
        Row(keys: "⌘Q", does: "quit the app under the ring; the overview stays up"),
        Row(keys: "⏎", does: "close on the window under the ring; on an empty workspace, switch to it"),
        Row(keys: "⌘ held", does: "a key on each window, 1–9 then a–f, in the order drawn; ⌘ + that key closes on it"),
        Row(keys: "Esc", does: "clear the query; on an empty query, dismiss, back on the window you came from"),
    ]

    public static let strip: [Row] = [
        Row(keys: "← → ↑ ↓", does: "move the marking through the app's windows, on to the next workspace, AeroSpace's focus going along"),
        Row(keys: "⌘← ⌘→", does: "the previous / next workspace, the row sliding with it"),
        Row(keys: "a workspace's name", does: "move the marking to that workspace: 3 for 3, 0 for 10"),
        Row(keys: "⇧⌘ + a key", does: "move the marked window to the workspace of that name; a new name creates it"),
        Row(keys: "⌘W / ⌘Q", does: "close the marked window / quit its app; the marking moves on"),
        Row(keys: "the app's key again", does: "move the marking on, as ⌘` does"),
        Row(keys: "⏎", does: "close on the marked window"),
        Row(keys: "⌘ held", does: "a key on each window, 1–9 then a–f, in the order drawn; ⌘ + that key closes on it"),
        Row(keys: "Esc", does: "dismiss, back on the window you came from"),
    ]
}
