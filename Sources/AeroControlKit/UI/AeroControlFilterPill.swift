import SwiftUI

/// What the user has typed and how much it found, over the grid the query is drawing. The
/// grid itself is the answer; the pill only says that the keystrokes are arriving, and —
/// when nothing matched and the full grid is back — why nothing moved.
struct AeroControlFilterPill: View {
    let query: String
    let matchCount: Int

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }

    var body: some View {
        if !query.isEmpty { pill }
    }

    /// Shown for any non-empty query, a miss included: otherwise one letter too many looks
    /// like the keystrokes stopped arriving.
    private var pill: some View {
        let single = matchCount == 1
        return HStack(spacing: 8) {
            Text(query)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text(matchCount == 0 ? "no match" : "\(matchCount)")
                .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                .opacity(0.75)
        }
        .foregroundStyle(single ? palette.focusedBadgeText : palette.badgeText)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(single ? palette.accent : palette.badgeFill, in: Capsule())
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .padding(.bottom, 10)
    }
}
