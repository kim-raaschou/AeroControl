import SwiftUI
import Common

/// What the user has typed, over the grid the query is drawing. The grid is the answer; the
/// pill only says the keystrokes are arriving, and — when nothing matched and the full grid
/// is back — why nothing moved.
///
/// Over the app strip it is the legend instead: the app, and one line per window with its key
/// and caption. The cards above are true to AeroSpace's geometry, which can be slivers; the
/// legend is where a window is read and picked whatever the geometry did.
struct AeroControlFilterPill: View {
    /// The app the strip shows, its icon, how many windows on how many workspaces, and its windows.
    private struct StripApp {
        let name: String
        let icon: NSImage?
        let summary: String
        let rows: [AppStripModel.LegendRow]
    }

    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    let matchCount: Int

    private var query: String { state.filter }

    /// The strip's app and its legend; or an app `open` could not find, named as the link named
    /// it, with why nothing came; nil on the map.
    private var app: StripApp? {
        if let missing = state.missingApp?.notFound { return StripApp(name: missing.name, icon: nil, summary: missing.reason, rows: []) }
        guard let strip = state.strip, let first = state.stripWindows.first?.window else { return nil }
        return StripApp(name: first.appName, icon: state.icon(for: strip.bundleId),
                        summary: AppStripModel.summary(windows: state.stripWindows.count, workspaces: state.stripWorkspaces.count),
                        rows: AppStripModel.legend(state.stripWindows, marked: strip.marked))
    }

    /// The lane is there whether or not anything has been typed. The pill is the only thing
    /// on screen that appears mid-gesture, and a view that appears must not move the grid it
    /// is describing.
    var body: some View {
        Group {
            if let app { appPill(app) } else if query.isEmpty { hint } else { pill }
        }
        .frame(height: Self.laneHeight(rows: app?.rows.count ?? 0))
    }

    /// The lane's idle content: the two keys the overview answers to, faint enough to be
    /// furniture. Nothing else on screen says the keyboard works, and a filter nobody can
    /// find is a filter nobody uses.
    private var hint: some View {
        Text("type to filter  ·  ⏎ focus")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(look.palette.badgeText.opacity(0.4))
    }

    /// The strip has no typing, so no hint: the app, then its windows one per line, the marked
    /// one in the accent. Each line is a key and a caption, so the pick is read here and made
    /// with the key, while the cards show where the window is.
    private func appPill(_ app: StripApp) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if let icon = app.icon {
                    PixelImage(image: icon, size: CGSize(width: 20, height: 20))
                }
                Text(app.name)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Text("· " + app.summary)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .opacity(0.75)
            }
            .frame(height: Self.laneHeight(rows: 0) - 14)
            ForEach(Array(app.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 10) {
                    Text(row.key ?? "")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .frame(width: 30, alignment: .trailing)
                        .opacity(row.key == nil ? 0 : 0.8)
                    Text(row.title)
                        .font(.system(size: 13, weight: row.marked ? .semibold : .medium, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: Self.titleWidth, alignment: .leading)
                    if let workspace = row.workspace {
                        Text("ws " + workspace)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .opacity(0.6)
                    }
                }
                .foregroundStyle(row.marked ? look.palette.accent : look.palette.badgeText)
                .frame(height: Self.rowHeight)
            }
        }
        .capsule(look.palette)
    }

    /// Tall enough for the capsule and its shadow, plus a line per window of the strip. The
    /// panel subtracts it from the grid's height, so the lane is reserved rather than added:
    /// typing never moves a card, and the strip's cards are drawn above the legend, not under it.
    static func laneHeight(rows: Int) -> CGFloat { 38 + CGFloat(rows) * rowHeight }
    private static let rowHeight: CGFloat = 20
    /// A caption is read, not studied: long paths and titles are cut in the middle past this.
    private static let titleWidth: CGFloat = 560

    /// Shown for any non-empty query, a miss included: otherwise one letter too many looks
    /// like the keystrokes stopped arriving. A miss has to say so — the grid it leaves
    /// standing is the same grid a query matching everything would leave.
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
            // A capsule at one line, a box with the same corners when the legend adds lines.
            .background(palette.badgeFill, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
