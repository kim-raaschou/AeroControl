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
    /// Preview tiles (3:2 snapshots) when Screen Recording is granted, plain icons otherwise.
    let showPreviews: Bool
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

    /// Narrow cards (empty workspaces) show only the badge, centered.
    private var isCompact: Bool { size.width < AeroControlLayout.minCardWidth }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        Group {
            if isCompact {
                badge.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    header.frame(height: AeroControlLayout.badgeLane - AeroControlLayout.cardPadding)
                    tiles.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .padding(AeroControlLayout.cardPadding)
        .frame(width: size.width, height: size.height)
        .background(shape.fill(.regularMaterial))
        .overlay(shape.strokeBorder(borderColor, lineWidth: isFocused ? 3 : 1))
        .overlay(dropTargetHint.allowsHitTesting(false))
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: onFocusWorkspace)
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

    private var header: some View {
        HStack(spacing: 10) {
            badge
            Text(workspace.windows.isEmpty ? "Empty" : "\(workspace.windows.count) window\(workspace.windows.count == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var badge: some View {
        Text(workspace.name)
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .lineLimit(1)
            .foregroundStyle(isFocused ? Color.white : .primary)
            .frame(width: 26, height: 26)
            .background(isFocused ? Color.accentColor : badgeFill, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(colorScheme == .dark ? 0.25 : 0.4), lineWidth: 1))
            .contentShape(Circle())
            .onTapGesture(perform: onFocusWorkspace)
            .draggable(OverviewDragPayload.workspace(name: workspace.name)) {
                Text(workspace.name).font(.system(size: 14, weight: .bold, design: .rounded)).padding(8)
            }
            .help(workspace.windows.isEmpty ? "Workspace \(workspace.name)"
                  : "Workspace \(workspace.name) — drag onto another workspace to merge")
    }

    private var badgeFill: Color {
        colorScheme == .dark ? .black.opacity(0.45) : .white.opacity(0.72)
    }

    @ViewBuilder private var tiles: some View {
        let windows = workspace.windows
        if windows.isEmpty {
            Color.clear
        } else {
            let aspect: CGFloat = showPreviews ? AeroControlLayout.tileAspect : 1
            let (columns, tileWidth) = AeroControlLayout.tileGrid(windowCount: windows.count, card: size, aspect: aspect)
            let metrics = showPreviews
                ? AeroControlMetrics(iconSize: tileWidth / 3, previews: true)
                : AeroControlMetrics(iconSize: tileWidth)
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
