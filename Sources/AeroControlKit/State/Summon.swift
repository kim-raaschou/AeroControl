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

    /// What this summon does while the overview is already up, showing the strip of `stripApp`
    /// or else the map. The strip's own key moves its marking on, as Cmd-` does. Another app's
    /// key only focuses that app, and the overview stays and follows it — the map mirrors
    /// AeroSpace, the strip turns to that app — so the keys bound to apps go on working through
    /// it: closing gave the keyboard back to the window from before, so the key for Claude
    /// brought Ghostty forward. Anything else closes the overview.
    public enum Again: Equatable, Sendable { case close, step, focus(app: String) }

    public func again(stripApp: String?) -> Again {
        switch (self, stripApp) {
        case (.focusedApp, .some): .step
        case (.app(let id), let strip?) where id == strip: .step
        case (.app(let id), _): .focus(app: id)
        default: .close
        }
    }
}
