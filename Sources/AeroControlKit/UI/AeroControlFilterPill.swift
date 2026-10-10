import SwiftUI
import Common

/// What the user has typed, over the grid the query is drawing.
struct AeroControlFilterPill: View {
    /// The app the strip shows, its icon, and its line: how many windows, and the marked one's title.
    private struct StripApp {
        let name: String
        let icon: NSImage?
        let summary: String
        /// The keys that work here, after the line.
        let keys: String
    }

    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    let matchCount: Int

    private var query: String { state.filter }

    /// The strip's app and its line; or an app `open` could not find, named as the link named it,
    /// with why nothing came; or, on the map once a key or the pointer has moved the ring, the
    /// window under it and its title, so a picture too small to read is read here; nil otherwise.
    private var app: StripApp? {
        if let missing = state.missingApp?.notFound { return StripApp(name: missing.name, icon: nil, summary: missing.reason, keys: "esc  close") }
        if let strip = state.strip, let first = state.stripWindows.first?.window {
            return StripApp(name: first.appName, icon: state.pictures.icon(for: strip.app ?? ""),
                            summary: AppStripModel.summary(state.stripWindows, marked: strip.marked), keys: "← → ↑ ↓ move  ·  ⌘← ⌘→ workspace  ·  ⏎ focus")
        }
        guard let marked = state.marking?.marked, let ringed = state.model.windowsInGridOrder.first(where: { $0.window.windowId == marked }) else { return nil }
        return StripApp(name: ringed.window.appName, icon: state.pictures.icon(for: ringed.window.bundleId), summary: ringed.window.caption + " · ws " + ringed.workspace, keys: Self.mapKeys)
    }
    /// The arrows and Enter only: the keys the cards do not show themselves (⌘1–⌘f, the workspaces'
    /// names) and the ones macOS makes standard (⌘W, ⌘Q, Escape) are left out.
    private static let mapKeys = "type to filter  ·  ← → ↑ ↓ move  ·  ⌘← ⌘→ ⌘↑ ⌘↓ workspace  ·  ⏎ focus"

    /// The lane is there whether or not anything has been typed.
    var body: some View {
        Group {
            if let app { appPill(app) } else if query.isEmpty { hint } else { pill }
        }
        .frame(height: AeroControlLayout.pillLane)
    }

    /// The lane's idle content: the keys the overview answers to, faint enough to be furniture.
    private var hint: some View { keys(Self.mapKeys) }

    private func keys(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(look.palette.badgeText.opacity(0.4))
    }

    /// The strip has no typing: one line, as high as the map's, so the cards keep their height and
    /// nothing moves as the marking does — the app, its line, and its keys after them.
    private func appPill(_ app: StripApp) -> some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                PixelImage(image: icon, size: CGSize(width: 20, height: 20))
            }
            Text(app.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            // Hugs its text: a bare maxWidth grew to it under the strip, which is wider.
            Text("· " + app.summary)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .opacity(0.75)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: Self.titleWidth, alignment: .leading)
                .fixedSize()
            keys(app.keys).padding(.leading, 12)
        }
        .capsule(look.palette)
    }

    /// Tall enough for the capsule and its shadow.
    private static let titleWidth: CGFloat = 560

    /// Shown for any non-empty query, a miss included: otherwise one letter too many looks like the
    /// keystrokes stopped arriving.
    private var pill: some View {
        HStack(spacing: 8) {
            Text(query)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            // One typed letter is not a miss — the map is simply still standing.
            if matchCount == 0, query.trimmingCharacters(in: .whitespaces).count >= OverviewModel.minQueryLength {
                Text("no match")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .opacity(0.75)
            }
        }
        .capsule(look.palette)
    }
}

private extension View {
    func capsule(_ palette: AeroControlPalette) -> some View {
        foregroundStyle(palette.badgeText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(palette.badgeFill, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
