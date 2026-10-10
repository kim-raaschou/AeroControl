import Foundation

/// What the overview opens showing: the whole map, or one app, so one key on an app does the
/// right thing whatever its state (`AppSummon.decide`).
///
/// An `aerocontrol://` link names it in AeroSpace's own words: `app-id=<bundle id>` or
/// `app-name=<name>` (spaces as `%20`) the app; `workspaces`, or anything else, the map. The
/// host keeps its case through Launch Services (measured 2026-10-04). A link reaches the
/// running instance the way a reopen does, without a second process — and unlike a reopen
/// it can carry a word.
public enum Summon: Equatable, Sendable {
    case map, app(AppRef)

    public init(_ url: URL) {
        let host = (url.host() ?? "").removingPercentEncoding ?? ""
        if host.hasPrefix("app-id="), host.count > 7 { self = .app(.bundleId(String(host.dropFirst(7)))) }
        else if host.hasPrefix("app-name="), host.count > 9 { self = .app(.name(String(host.dropFirst(9)))) }
        else { self = .map }
    }

    /// What this summon does while the overview is already up, showing the strip of `stripApp`
    /// or else the map. The strip's own key moves its marking on, as Cmd-` does. Any other
    /// app's key is that app's whole flow again — start, focus, toggle, or its strip taking
    /// over from whatever was up — so an app key means the same whether the overview is up or
    /// not. The map's key closes.
    public enum Again: Equatable, Sendable { case close, step, summon(AppRef) }

    public func again(stripApp: String?, among windows: [WindowInfo]) -> Again {
        switch self {
        case .map: .close
        case .app(let ref): stripApp.map { ref.identifies(bundleId: $0, among: windows) } == true ? .step : .summon(ref)
        }
    }
}
