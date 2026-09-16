import SwiftUI
import Common

/// A workspace drawn as a map of the screen: each window's frame, and the outline of all.
struct WorkspaceMap {
    let frames: [CGRect]
    let bounds: CGRect
}

/// One "desktop" card: badge at the top-left, the workspace's windows below, as a map of
/// the screen when their frames are known, otherwise as a grid of snapshot cells or icons.
/// Drop target for window tiles (move) and workspace cards (merge).
struct AeroControlWorkspaceCard: View {
    let workspace: WorkspaceInfo
    /// The display this workspace lives on; nil with a single display, where naming it is noise.
    let monitorName: String?
    let isFocused: Bool
    let focusedWindowId: Int
    let icons: [Int: NSImage]
    let previews: [Int: NSImage]
    /// The windows' on-screen frames (in window order) and their outline, when the card is a
    /// map of the screen instead of a grid. Decided by the panel, which also sizes the card.
    let map: WorkspaceMap?
    /// Preview tiles (snapshot cells) when Screen Recording is granted, plain icons otherwise.
    let showPreviews: Bool
    /// Height/width of a snapshot cell, the screen's own aspect.
    let previewAspect: CGFloat
    let size: CGSize
    let onFocusWorkspace: () -> Void
    let onFocusWindow: (Int) -> Void
    let onMoveWindow: (Int, String) -> Void
    /// (source workspace, target workspace): merge every window of source into target.
    let onMergeWorkspace: (String, String) -> Void
    let onCloseWindow: (Int) -> Void

    @State private var isDropTarget = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

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
        .onTapGesture(perform: onFocusWorkspace)
        // Grab the card anywhere outside a tile and drop it on another card to merge the
        // workspace into it. Tiles keep their own drag (a single window).
        .draggable(OverviewDragPayload.workspace(name: workspace.name)) { dragPreview }
        .dropDestination(for: OverviewDragPayload.self) { items, _ in
            guard let item = items.first else { return false }
            isDropTarget = false
            switch item {
            case .window(let id):
                onMoveWindow(id, workspace.name)
            case .workspace(let source):
                guard source != workspace.name else { return false }
                onMergeWorkspace(source, workspace.name)
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
            .onTapGesture(perform: onFocusWorkspace)
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
        if workspace.windows.isEmpty {
            Color.clear
        } else if let map {
            screenMap(AeroControlLayout.minimap(frames: map.frames, bounds: map.bounds, in: innerSize))
        } else {
            grid
        }
    }

    /// The windows drawn where AeroSpace put them. Floating windows come last so they lie on
    /// top of the tiles they cover on the real screen, which is the whole point of floating.
    private func screenMap(_ cells: [CGRect]) -> some View {
        let placed = zip(workspace.windows, cells).sorted { !$0.0.isFloating && $1.0.isFloating }
        return ZStack(alignment: .topLeading) {
            ForEach(Array(placed), id: \.0.windowId) { window, cell in
                tile(window, metrics: .fitting(cellWidth: cell.width, previews: true, previewAspect: cell.height / cell.width))
                    .offset(x: cell.minX, y: cell.minY)
            }
        }
        .frame(width: innerSize.width, height: innerSize.height, alignment: .topLeading)
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
        AeroControlAppTile(
            window: window,
            image: icons[window.windowId],
            preview: previews[window.windowId],
            isFocused: window.windowId == focusedWindowId,
            onFocusWindow: { onFocusWindow(window.windowId) },
            onCloseWindow: { onCloseWindow(window.windowId) },
            metrics: metrics
        )
    }

    @ViewBuilder private var dropTargetHint: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(palette.accent.opacity(0.9), lineWidth: 3)
                .background(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(palette.accent.opacity(0.12)))
        }
    }
}
