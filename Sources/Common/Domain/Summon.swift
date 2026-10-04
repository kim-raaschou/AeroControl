import Foundation

/// What the overview opens showing: the whole map, or one app, so one key on an app does the
/// right thing whatever its state (`AppSummon.decide`).
///
/// An `aerocontrol://` link names it: `aerocontrol://<bundle id>` the app — the bundle id is the
/// host, which keeps its case through Launch Services (measured 2026-10-04) — and
/// `aerocontrol://workspaces`, or any host without a dot, the map. A link reaches the running instance the way a reopen does, without
/// a second process — and unlike a reopen it can carry a word.
public enum Summon: Equatable, Sendable {
    case map, app(bundleId: String)

    public init(_ url: URL) {
        // A bundle id has a dot in it; a word, `workspaces` or anything else, is the map.
        let host = url.host() ?? ""
        self = host.contains(".") ? .app(bundleId: host) : .map
    }

    /// What this summon does while the overview is already up, showing the strip of `stripApp`
    /// or else the map. The strip's own key moves its marking on, as Cmd-` does. Any other
    /// app's key is that app's whole flow again — start, focus, toggle, or its strip taking
    /// over from whatever was up — so an app key means the same whether the overview is up or
    /// not. The map's key closes.
    public enum Again: Equatable, Sendable { case close, step, summon(app: String) }

    public func again(stripApp: String?) -> Again {
        switch (self, stripApp) {
        case (.map, _): .close
        case (.app(let id), let strip?) where id == strip: .step
        case (.app(let id), _): .summon(app: id)
        }
    }
}
