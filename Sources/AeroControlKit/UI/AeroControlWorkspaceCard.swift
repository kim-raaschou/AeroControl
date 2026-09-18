import SwiftUI
import Common

/// One "desktop" card: badge at the top-left, the workspace's windows below as a grid of
/// snapshot cells (or app icons without Screen Recording).
/// Drop target for window tiles (move) and workspace cards (merge).
struct AeroControlWorkspaceCard: View {
    let workspace: WorkspaceInfo
    /// The display this workspace lives on; nil with a single display, where naming it is noise.
    let monitorName: String?
    /// Height/width of a snapshot cell, the screen's own aspect.
    let previewAspect: CGFloat
    let size: CGSize
    /// Whether this card is part of a filtered result rather than the map.
    let filtering: Bool

    @State private var isDropTarget = false
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroDismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

    private var isFocused: Bool { workspace.name == state.model.focusedWorkspace }
    /// Preview tiles (snapshot cells) when Screen Recording is granted, plain icons otherwise.
    private var showPreviews: Bool { state.previewsAvailable }

    private func run(_ action: AeroControlAction) {
        state.send(.action(action))
    }

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }

    private static let cornerRadius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        // Same header lane on every card, so the badge sits in the same corner whether the
        // workspace is empty (a narrow card) or full.
        // The tile area gets a fixed frame: a grid that overflowed would otherwise widen the
        // stack and push the badge out of its corner.
        VStack(alignment: .leading, spacing: 0) {
            header.frame(height: AeroControlLayout.badgeLane - AeroControlLayout.cardPadding)
            tiles.frame(width: innerSize.width, height: innerSize.height)
        }
        .padding(AeroControlLayout.cardPadding)
        .frame(width: size.width, height: size.height)
        .background(cardFill(shape))
        .overlay(shape.strokeBorder(palette.cardBorder, lineWidth: 1))   // focus shows on the badge and the window, not the card
        .overlay(dropTargetHint.allowsHitTesting(false))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { run(.focusWorkspace(workspace.name)); dismiss() }
        // Grab the card anywhere outside a tile and drop it on another card to merge the
        // workspace into it. Tiles keep their own drag (a single window).
        .draggable(OverviewDragPayload.workspace(name: workspace.name)) { dragPreview }
        .dropDestination(for: OverviewDragPayload.self) { items, _ in
            guard let item = items.first else { return false }
            isDropTarget = false
            switch item {
            case .window(let id):
                run(.moveWindow(windowId: id, toWorkspace: workspace.name))
            case .workspace(let source):
                guard source != workspace.name else { return false }
                run(.mergeWorkspace(source: source, into: workspace.name))
            }
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    /// A solid themed fill, or the platform's frosted glass when the theme is System.
    @ViewBuilder private func cardFill(_ shape: RoundedRectangle) -> some View {
        if let fill = palette.cardFill { shape.fill(fill) } else { shape.fill(.regularMaterial) }
    }

    /// The badge, and with more than one display the name of this workspace's. The tiles
    /// say how many windows there are.
    private var header: some View {
        HStack(spacing: 6) {
            badge
            if let monitorName, !monitorName.isEmpty {
                Label(monitorName, systemImage: "display")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.badgeText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
    }

    /// The workspace name as a quiet monogram: a filled circle with no outline, in the
    /// accent color for the focused workspace and a faint tint otherwise.
    private var badge: some View {
        Text(workspace.name)
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .foregroundStyle(isFocused ? palette.focusedBadgeText : palette.badgeText)
            .frame(width: AeroControlLayout.badgeSize, height: AeroControlLayout.badgeSize)
            .background(isFocused ? palette.accent : palette.badgeFill, in: Circle())
            .contentShape(Circle())
            .onTapGesture { run(.focusWorkspace(workspace.name)); dismiss() }
            .help(workspace.windows.isEmpty ? "Workspace \(workspace.name)"
                  : "Workspace \(workspace.name) — drag the card onto another workspace to merge")
    }

    /// What follows the cursor while a workspace is dragged: its badge, a little larger.
    private var dragPreview: some View {
        Text(workspace.name)
            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(palette.focusedBadgeText)
            .frame(width: 32, height: 32)
            .background(palette.accent, in: Circle())
            .padding(6)
    }

    private var innerSize: CGSize {
        CGSize(width: size.width - 2 * AeroControlLayout.cardPadding,
               height: size.height - AeroControlLayout.cardPadding - AeroControlLayout.badgeLane)
    }

    @ViewBuilder private var tiles: some View {
        if workspace.windows.isEmpty { Color.clear } else { grid }
    }

    private var grid: some View {
        let windows = workspace.windows
        let aspect: CGFloat = showPreviews ? previewAspect : 1
        let (columns, tileWidth) = AeroControlLayout.tileGrid(windowCount: windows.count, card: size, aspect: aspect)
        let metrics = AeroControlMetrics.fitting(cellWidth: tileWidth, previews: showPreviews, previewAspect: previewAspect)
        return LazyVGrid(
            columns: Array(repeating: GridItem(.fixed(metrics.tileWidth), spacing: AeroControlLayout.tileSpacing), count: columns),
            spacing: AeroControlLayout.tileSpacing
        ) {
            ForEach(windows, id: \.windowId) { window in tile(window, metrics: metrics) }
        }
        .animation(.easeInOut(duration: 0.15), value: windows)
    }

    private func tile(_ window: WindowInfo, metrics: AeroControlMetrics) -> AeroControlAppTile {
        AeroControlAppTile(window: window, metrics: metrics, filtering: filtering)
    }

    @ViewBuilder private var dropTargetHint: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(palette.accent.opacity(0.12))
                .strokeBorder(palette.accent.opacity(0.9), lineWidth: 3)
        }
    }
}
