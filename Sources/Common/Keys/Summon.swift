import Foundation

public enum Summon: Equatable, Sendable {
    case map, app(AppRef)

    public init(_ url: URL) {
        let host = (url.host() ?? "").removingPercentEncoding ?? ""
        if host.hasPrefix("app-id="), host.count > 7 { self = .app(.bundleId(String(host.dropFirst(7)))) }
        else if host.hasPrefix("app-name="), host.count > 9 { self = .app(.name(String(host.dropFirst(9)))) }
        else { self = .map }
    }

    public enum Again: Equatable, Sendable { case close, step, summon(AppRef) }

    public func again(stripApp: String?, among windows: [WindowInfo]) -> Again {
        switch self {
        case .map: .close
        case .app(let ref): stripApp.map { ref.identifies(bundleId: $0, among: windows) } == true ? .step : .summon(ref)
        }
    }
}
