import SwiftUI
import Common

/// What the user has typed, over the grid the query is drawing. The grid is the answer; the
/// pill only says the keystrokes are arriving, and — when nothing matched and the full grid
/// is back — why nothing moved.
///
/// Over the app strip it names the app and the marked window instead, on the same one line,
/// so the strip's cards keep the map's height. A window too small to read is read here by
/// pointing at it, which marks it.
struct AeroControlFilterPill: View {
    /// The app the strip shows, its icon, and its line: how many windows, and the marked one's title.
    private struct StripApp {
        let name: String
        let icon: NSImage?
        let summary: String
    }

    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    let matchCount: Int

    private var query: String { state.filter }

    /// The strip's app and its line; or an app `open` could not find, named as the link named
    /// it, with why nothing came; nil on the map.
    private var app: StripApp? {
        if let missing = state.missingApp?.notFound { return StripApp(name: missing.name, icon: nil, summary: missing.reason) }
        guard let strip = state.strip, let first = state.stripWindows.first?.window else { return nil }
        return StripApp(name: first.appName, icon: state.icon(for: strip.app ?? ""),
                        summary: AppStripModel.summary(state.stripWindows, marked: strip.marked))
    }

    /// The lane is there whether or not anything has been typed. The pill is the only thing
    /// on screen that appears mid-gesture, and a view that appears must not move the grid it
    /// is describing.
    var body: some View {
        Group {
            if let app { appPill(app) } else if query.isEmpty { hint } else { pill }
        }
        .frame(height: AeroControlLayout.pillLane)
    }

    /// The lane's idle content: the two keys the overview answers to, faint enough to be
    /// furniture. Nothing else on screen says the keyboard works, and a filter nobody can
    /// find is a filter nobody uses.
    private var hint: some View {
        Text("type to filter  ·  ⏎ focus")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(look.palette.badgeText.opacity(0.4))
    }

    /// The strip has no typing, so no hint: one line, as high as the map's, so the cards keep
    /// their height and nothing moves as the marking does — the app, and its line.
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
        }
        .capsule(look.palette)
    }

    /// Tall enough for the capsule and its shadow. The panel subtracts it from the grid's height,
    /// so the lane is reserved rather than added: typing never moves a card.
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
            .background(palette.badgeFill, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
