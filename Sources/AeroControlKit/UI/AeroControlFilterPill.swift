import SwiftUI
import Common

/// What the user has typed, over the grid the query is drawing. The grid is the answer; the
/// pill only says the keystrokes are arriving, and — when nothing matched and the full grid
/// is back — why nothing moved.
struct AeroControlFilterPill: View {
    let query: String
    let matchCount: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }


    /// The lane is there whether or not anything has been typed. The pill is the only thing
    /// on screen that appears mid-gesture, and a view that appears must not move the grid it
    /// is describing.
    var body: some View {
        Group {
            if query.isEmpty { Color.clear } else { pill }
        }
        .frame(height: Self.laneHeight)
    }

    /// Tall enough for the capsule and its shadow. The panel subtracts it from the grid's
    /// height, so the lane is reserved rather than added and typing never moves a card.
    static let laneHeight: CGFloat = 38

    /// Shown for any non-empty query, a miss included: otherwise one letter too many looks
    /// like the keystrokes stopped arriving. A miss has to say so — the grid it leaves
    /// standing is the same grid a query matching everything would leave.
    private var pill: some View {
        let single = matchCount == 1
        return HStack(spacing: 8) {
            Text(query)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            // One typed letter is not a miss — the map is simply still standing.
            if matchCount == 0, query.trimmingCharacters(in: .whitespaces).count >= OverviewModel.minQueryLength {
                Text("no match")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .opacity(0.75)
            }
        }
        .foregroundStyle(single ? palette.focusedBadgeText : palette.badgeText)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(single ? palette.accent : palette.badgeFill, in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
