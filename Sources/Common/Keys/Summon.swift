import Foundation

public enum Summon: Equatable, Sendable {
    case map, app(AppRef)

    public init(_ url: URL) {
        let host = (url.host() ?? "").removingPercentEncoding ?? ""
        if host.hasPrefix("app-id="), host.count > 7 { self = .app(.bundleId(String(host.dropFirst(7)))) }
        else if host.hasPrefix("app-name="), host.count > 9 { self = .app(.name(String(host.dropFirst(9)))) }
        else { self = .map }
    }
}

public enum AppRef: Equatable, Sendable {
    case bundleId(String)
    case name(String)

    func matches(_ window: WindowInfo) -> Bool {
        switch self {
        case .bundleId(let id): window.bundleId == id
        case .name(let name): window.appName == name
        }
    }

    var notFound: (name: String, reason: String) {
        switch self {
        case .bundleId(let id): (id, "no app has this id")
        case .name(let name): (name, "no app has this name")
        }
    }
}
