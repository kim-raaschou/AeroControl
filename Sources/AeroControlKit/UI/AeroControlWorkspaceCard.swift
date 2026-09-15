import SwiftUI
import Common

/// One "desktop" card: badge at the top-left, the workspace's windows as 3:2 tiles in a
/// grid below. Drop target for window tiles (move) and workspace badges (merge).
struct AeroControlWorkspaceCard: View {
    let workspace: WorkspaceInfo
    let isFocused: Bool
    let focusedWindowId: Int
    let icons: [Int: NSImage]
    let previews: [Int: NSImage]
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

    private static let cornerRadius: CGFloat = 18

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        // Same header lane on every card, so the badge sits in the same corner whether the
        // workspace is empty (a narrow card) or full.
        // The tile area gets a fixed frame: a grid that overflowed would otherwise widen the
        // stack and push the badge out of its corner.
        VStack(alignment: .leading, spacing: 0) {
            header.frame(height: AeroControlLayout.badgeLane - AeroControlLayout.cardPadding)
            tiles.frame(width: size.width - 2 * AeroControlLayout.cardPadding,
                        height: size.height - AeroControlLayout.cardPadding - AeroControlLayout.badgeLane)
        }
        .padding(AeroControlLayout.cardPadding)
        .frame(width: size.width, height: size.height)
        .background(shape.fill(.regularMaterial))
        .overlay(shape.strokeBorder(borderColor, lineWidth: isFocused ? AeroControlMetrics.focusRingWidth : 1))
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

    private var borderColor: Color {
        if isFocused { return .accentColor }
        return colorScheme == .dark ? .white.opacity(0.18) : .black.opacity(0.12)
    }

    /// Just the badge; the tiles say how many windows there are.
    private var header: some View {
        HStack(spacing: 0) {
            badge
            Spacer(minLength: 0)
        }
    }

    /// The workspace name as a quiet monogram: a filled circle with no outline, in the
    /// accent color for the focused workspace and a faint tint otherwise.
    private var badge: some View {
        Text(workspace.name)
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .foregroundStyle(isFocused ? Color.white : .secondary)
            .frame(width: AeroControlLayout.badgeSize, height: AeroControlLayout.badgeSize)
            .background(isFocused ? Color.accentColor : badgeFill, in: Circle())
            .contentShape(Circle())
            .onTapGesture(perform: onFocusWorkspace)
            .help(workspace.windows.isEmpty ? "Workspace \(workspace.name)"
                  : "Workspace \(workspace.name) — drag the card onto another workspace to merge")
    }

    /// What follows the cursor while a workspace is dragged: its badge, a little larger.
    private var dragPreview: some View {
        Text(workspace.name)
            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Color.white)
            .frame(width: 32, height: 32)
            .background(Color.accentColor, in: Circle())
            .padding(6)
    }

    private var badgeFill: Color {
        colorScheme == .dark ? .white.opacity(0.10) : .black.opacity(0.07)
    }

    @ViewBuilder private var tiles: some View {
        let windows = workspace.windows
        if windows.isEmpty {
            Color.clear
        } else {
            let aspect: CGFloat = showPreviews ? previewAspect : 1
            let (columns, tileWidth) = AeroControlLayout.tileGrid(windowCount: windows.count, card: size, aspect: aspect)
            let metrics = AeroControlMetrics.fitting(cellWidth: tileWidth, previews: showPreviews, previewAspect: previewAspect)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(metrics.tileWidth), spacing: AeroControlLayout.tileSpacing), count: columns),
                spacing: AeroControlLayout.tileSpacing
            ) {
                ForEach(windows, id: \.windowId) { window in
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
            }
            .animation(.easeInOut(duration: 0.15), value: windows)
        }
    }

    @ViewBuilder private var dropTargetHint: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.9), lineWidth: 3)
                .background(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(Color.accentColor.opacity(0.12)))
        }
    }
}
