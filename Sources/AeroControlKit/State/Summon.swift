import Foundation

/// What the overview opens showing: the whole map; the app of the focused window — the
/// summon for "which of my three Arc windows"; or a named app, so one key on an app does the
/// right thing whatever its state. What that is: `OverviewStore.summonApp`.
///
/// An `aerocontrol://` link names it: `workspaces` (or anything else) the map, `windows` the
/// focused app, `windows?app=<bundle id>` a named one. A link reaches the running instance
/// the way a reopen does, without a second process — and unlike a reopen it can carry a word.
public enum Summon: Equatable, Sendable {
    case map, focusedApp, app(bundleId: String)

    public init(_ url: URL) {
        guard url.host() == "windows" else { self = .map; return }
        let app = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "app" }?.value
        self = app.map { .app(bundleId: $0) } ?? .focusedApp
    }
}
