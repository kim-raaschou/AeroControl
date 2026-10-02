import SwiftUI
import Common

/// What the user has typed, over the grid the query is drawing. The grid is the answer; the
/// pill only says the keystrokes are arriving, and — when nothing matched and the full grid
/// is back — why nothing moved.
///
/// Over the app strip it names the app instead: the strip is the map narrowed to one app, so it
/// says so where the map says what it is narrowed to.
struct AeroControlFilterPill: View {
    /// The app the strip shows, its icon, the marked window's title, and how many windows on how many workspaces.
    struct StripApp {
        let name: String
        let icon: NSImage?
        let title: String?
        let summary: String
    }

    let query: String
    let matchCount: Int
    var app: StripApp?

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }

    /// The lane is there whether or not anything has been typed. The pill is the only thing
    /// on screen that appears mid-gesture, and a view that appears must not move the grid it
    /// is describing.
    var body: some View {
        Group {
            if let app { appPill(app) } else if query.isEmpty { hint } else { pill }
        }
        .frame(height: Self.laneHeight)
    }

    /// The lane's idle content: the three keys the overview answers to, faint enough to be
    /// furniture. Nothing else on screen says the keyboard works, and a filter nobody can
    /// find is a filter nobody uses.
    private var hint: some View {
        Text("type to filter  ·  ⇥ next  ·  ⏎ focus")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(palette.badgeText.opacity(0.4))
    }

    /// The strip has no typing, so no hint: the app, in the capsule a query is drawn in.
    private func appPill(_ app: StripApp) -> some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                PixelImage(image: icon, size: CGSize(width: 20, height: 20))
            }
            Text(app.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if let title = app.title {
                Text("— " + title)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text("· " + app.summary)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .opacity(0.75)
        }
        .capsule(palette)
    }

    /// Tall enough for the capsule and its shadow. The panel subtracts it from the grid's
    /// height, so the lane is reserved rather than added and typing never moves a card.
    static let laneHeight: CGFloat = 38

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
        .capsule(palette)
    }
}

private extension View {
    func capsule(_ palette: AeroControlPalette) -> some View {
        foregroundStyle(palette.badgeText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(palette.badgeFill, in: Capsule())
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
