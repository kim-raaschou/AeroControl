import Foundation

/// How a link names an app: by the two names AeroSpace itself uses for one, its bundle id
/// (`app-id` in AeroSpace's config, `app-bundle-id` in `list-windows`) or its name (`app-name`).
public enum AppRef: Equatable, Sendable {
    case bundleId(String)
    case name(String)

    /// Whether this window is the app's.
    public func matches(_ window: WindowInfo) -> Bool {
        switch self {
        case .bundleId(let id): window.bundleId == id
        case .name(let name): window.appName == name
        }
    }

    /// Whether this names the app a strip is showing, which the strip knows by bundle id: resolved
    /// through the windows on the map, which a strip always has some of.
    public func identifies(bundleId: String, among windows: [WindowInfo]) -> Bool {
        windows.contains { $0.bundleId == bundleId && matches($0) }
    }

    /// What the strip's lane says when `open` found no such app: the name as the link gave it,
    /// in the app's place, and why nothing came, in its count's.
    public struct NotFound: Equatable, Sendable {
        public let name: String
        public let reason: String
    }

    public var notFound: NotFound {
        switch self {
        case .bundleId(let id): NotFound(name: id, reason: "no app has this id")
        case .name(let name): NotFound(name: name, reason: "no app has this name")
        }
    }
}
