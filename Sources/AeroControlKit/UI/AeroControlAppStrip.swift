import SwiftUI
import Common

/// The picker for "which of this app's windows", drawn like macOS's own switcher: one
/// rounded panel in the middle of the screen, the app's icon and name over one row of its
/// windows, grouped by workspace with the workspace named under each group. Every tile at
/// its own shape, all at one height; the ring on the one Enter picks, the window you came
/// from framed. The same keys as the map: Tab and ←/→ walk the row, Enter picks, Escape
/// leaves, typing narrows.
struct AeroControlAppStrip: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme
    @Environment(\.aeroMotion) private var motion

    let matches: [ParsedWindow]
    let usable: CGSize
    let fallbackRatio: CGFloat

    private static let margin: CGFloat = 48
    private static let padding: CGFloat = 24
    private static let cornerRadius: CGFloat = 22

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }
    private var groups: [WorkspaceInfo] { state.model.workspaces(holding: matches) }

    private var layout: AppStripLayout.Layout {
        AppStripLayout.layout(
            groups: groups.map { AeroControlLayout.ratios(of: $0.windows, sizes: state.previewSizes, fallback: fallbackRatio) },
            viewWidth: usable.width - 2 * (Self.margin + Self.padding), panelHeight: usable.height,
            tileGap: AeroControlLayout.tileSpacing, groupGap: AeroControlLayout.cardGap, caption: AeroControlLayout.captionLane)
    }

    var body: some View {
        let layout = self.layout
        let groups = self.groups
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return VStack(spacing: 18) {
            header
            HStack(alignment: .top, spacing: AeroControlLayout.cardGap) {
                ForEach(Array(groups.enumerated()), id: \.element.id) { g, workspace in
                    group(workspace, layout.groups[g])
                }
            }
        }
        .padding(Self.padding)
        .background { if let fill = palette.cardFill { shape.fill(fill) } else { shape.fill(.regularMaterial) } }
        .overlay(shape.strokeBorder(palette.cardBorder, lineWidth: 1))
        .clipShape(shape)
        .animation(.easeInOut(duration: 0.15 * motion), value: matches)
        .onChange(of: groups.map { $0.windows.map(\.windowId) }, initial: true) { _, rows in   // for the arrows
            state.cardRows = [groups.map(\.name)]
            for (workspace, ids) in zip(groups, rows) { state.tileRows[workspace.name] = [ids] }
        }
    }

    /// The app's icon and name, and how many windows on how many workspaces.
    private var header: some View {
        HStack(spacing: 10) {
            if let first = matches.first?.window {
                if let icon = state.icons[first.bundleId] {
                    Image(nsImage: icon).resizable().interpolation(.high).frame(width: 22, height: 22)
                }
                Text(first.appName).font(.system(size: 15, weight: .semibold))
            }
            Text("· \(matches.count) windows" + (groups.count > 1 ? " on \(groups.count) workspaces" : ""))
                .font(.system(size: 15))
                .opacity(0.7)
        }
        .foregroundStyle(palette.badgeText)
    }

    /// One workspace's windows in a row, the workspace named under them — in the accent
    /// while the ring is in this group.
    private func group(_ workspace: WorkspaceInfo, _ laid: AppStripLayout.Group) -> some View {
        let ringHere = workspace.windows.contains { $0.windowId == state.ringWindowId }
        return VStack(spacing: 10) {
            HStack(alignment: .top, spacing: AeroControlLayout.tileSpacing) {
                ForEach(Array(workspace.windows.enumerated()), id: \.element.windowId) { i, window in
                    AeroControlAppTile(window: window,
                                       metrics: AeroControlMetrics(tileSize: CGSize(width: laid.tiles[i].width, height: laid.tiles[i].height)),
                                       filtering: true)
                }
            }
            Text(workspace.name)
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(ringHere ? palette.accent : palette.badgeText.opacity(0.6))
        }
    }
}
