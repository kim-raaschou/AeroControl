import Foundation

public enum AppRef: Equatable, Sendable {
    case bundleId(String)
    case name(String)

    public func matches(_ window: WindowInfo) -> Bool {
        switch self {
        case .bundleId(let id): window.bundleId == id
        case .name(let name): window.appName == name
        }
    }

    public func identifies(bundleId: String, among windows: [WindowInfo]) -> Bool {
        windows.contains { $0.bundleId == bundleId && matches($0) }
    }

    public var notFound: (name: String, reason: String) {
        switch self {
        case .bundleId(let id): (id, "no app has this id")
        case .name(let name): (name, "no app has this name")
        }
    }
}
