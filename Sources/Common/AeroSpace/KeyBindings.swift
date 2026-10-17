import Foundation

public struct KeyBinding: Equatable, Sendable {
    public let mode: String
    public let keys: String
    public let command: String

    public var app: String? {
        ["aerocontrol://app-id=", "aerocontrol://app-name=", "open -b \"", "open -a \""].lazy.compactMap { marker in
            command.range(of: marker).flatMap { String(command[$0.upperBound...].prefix { !"\" ;".contains($0) }).removingPercentEncoding }
        }.first
    }

    public var does: String {
        command.replacingOccurrences(of: "exec-and-forget", with: "").replacingOccurrences(of: "; mode main", with: "")
            .replacingOccurrences(of: " --(boundaries(-action)?|window-id|workspace|monitor) \\S+| --[\\w-]+", with: "", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    var order: String {
        let key = keys.split(separator: "-").last ?? "", functionKey = key.hasPrefix("f") && Int(key.dropFirst()) != nil
        return (does == "mode main" ? "9" : String(keys.split(separator: "-").count - 1)) + (functionKey ? "1 " : "0 ") + chord
    }

    public var chord: String {
        let parts = keys.split(separator: "-").map(String.init), key = parts.last ?? ""
        let held = [("ctrl", "⌃"), ("alt", "⌥"), ("shift", "⇧"), ("cmd", "⌘")].filter { parts.dropLast().contains($0.0) }.map(\.1).joined()
        let shown = ["left": "←", "right": "→", "up": "↑", "down": "↓"][key] ?? key
        return held.isEmpty ? shown : held + " " + shown
    }
}

public func parseBindings(json: String) throws -> [KeyBinding] {
    let modes = try JSONDecoder().decode([String: [String: [String: String]]].self, from: Data(json.utf8))
    return modes.sorted { ($0.key == "main" ? 0 : 1, $0.key) < ($1.key == "main" ? 0 : 1, $1.key) }.flatMap { mode, sections in
        (sections["binding"] ?? [:]).map { KeyBinding(mode: mode, keys: $0.key, command: $0.value) }
            .sorted { $0.order.localizedStandardCompare($1.order) == .orderedAscending }
    }
}

public func loadBindings(using runner: AerospaceProcessRunner) async -> [KeyBinding] {
    (try? await runner.run(AerospaceCommand.modes)).flatMap { try? parseBindings(json: $0) } ?? []
}
