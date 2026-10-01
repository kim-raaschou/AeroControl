import SwiftUI
import Common

/// One "desktop" card: badge at the top-left, the workspace's windows below as a grid of
/// snapshot cells.
/// Drop target for window tiles (move) and workspace cards (merge).
struct AeroControlWorkspaceCard: View {
    let workspace: WorkspaceInfo
    /// The display this workspace lives on; nil with a single display, where naming it is noise.
    let monitorName: String?
    /// Width / height of a window whose size is not known yet: the screen's own shape.
    let fallbackRatio: CGFloat
    /// The visible frame of the screen this workspace lives on, in AeroSpace's coordinates
    /// (points, top-left origin); the area its layout fills.
    let screen: CGRect?
    /// The gap AeroSpace keeps between windows, as the overview read it; nil when no workspace showed it.
    let gap: CGFloat?
    let size: CGSize
    /// Whether this card is part of a filtered result rather than the map.
    let filtering: Bool

    @State private var isDropTarget = false
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroDismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme
    @Environment(\.aeroMotion) private var motion

    private func run(_ action: AeroControlAction) {
        state.send(.action(action))
    }

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous)
        let placement = self.placement
        AeroControlCardFace(workspace: workspace, monitorName: monitorName, orderUnknown: placement.fromTree && !placement.exact, size: size) {
            grid(placement)
        }
        .overlay(dropTargetHint.allowsHitTesting(false))
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
                // Dropped back where it came from: nothing to move, like a card on itself.
                guard !workspace.windows.contains(where: { $0.windowId == id }) else { return false }
                run(.moveWindow(windowId: id, toWorkspace: workspace.name))
            case .workspace(let source):
                guard source != workspace.name else { return false }
                run(.mergeWorkspace(source: source, into: workspace.name))
            }
            return true
        } isTargeted: { isDropTarget = $0 }
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

    private var innerSize: CGSize { AeroControlLayout.innerSize(of: size) }

    /// Where every window goes in the card's inner box, how they read as rows for ↑/↓,
    /// whether that is the workspace's real tree rather than packed tiles, and which windows
    /// float over the tree rather than sit in it.
    private typealias Placement = (frames: [Int: CGRect], rows: [[Int]], fromTree: Bool, ghosts: Set<Int>, exact: Bool)

    /// The workspace as AeroSpace lays it out when that can be read from the windows' sizes
    /// and the root's axis (`AeroControlLayout.treeLayout`); otherwise `TilePacker`'s tiles,
    /// each at its own shape at one shared picture height, centred in the inner box. A
    /// filtered card shows a subset, whose sizes cannot add up to a tree, so it packs.
    private var placement: Placement {
        let windows = workspace.windows
        let inner = innerSize
        if !filtering, let tree = AeroControlLayout.treeLayout(windows: windows, sizes: state.previewSizes, rootLayout: workspace.rootLayout,
                                                              screen: screen, gap: gap, inner: inner) {
            return (tree.frames, tree.rows, fromTree: true, ghosts: tree.ghosts, exact: tree.exact)
        }
        let ratios = AeroControlLayout.ratios(of: windows, sizes: state.previewSizes, fallback: fallbackRatio)
        let packed = AeroControlLayout.packTiles(ratios: ratios, inner: inner,
                                                 gap: AeroControlLayout.tileGap(innerGap: gap, screen: screen?.size, inner: inner),
                                                 caption: filtering ? AeroControlLayout.captionLane : 0)
        let origin = AeroControlLayout.tileOrigin(packed: CGSize(width: packed.width, height: packed.height), inner: inner)
        let frames = Dictionary(zip(windows.map(\.windowId), packed.tiles.map { CGRect(x: origin.x + $0.x, y: origin.y + $0.y, width: $0.width, height: $0.height) }),
                                uniquingKeysWith: { _, b in b })
        return (frames, packed.rows.map { $0.map { windows[$0].windowId } }, fromTree: false, ghosts: [], exact: false)
    }

    private func grid(_ placement: Placement) -> some View {
        let windows = workspace.windows
        let inner = innerSize
        return ZStack(alignment: .topLeading) {
            ForEach(windows, id: \.windowId) { window in
                let frame = placement.frames[window.windowId] ?? .zero
                let ghost = placement.ghosts.contains(window.windowId)
                tile(window, metrics: AeroControlMetrics(tileSize: frame.size))
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(ghost ? 0.7 : 1)          // see-through, as krn.overview draws a float: what lies under it shows
                    .zIndex(ghost ? 1 : 0)
            }
        }
        .frame(width: inner.width, height: inner.height, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.15 * motion), value: windows)
        .onChange(of: placement.rows, initial: true) { _, rows in state.tileRows[workspace.name] = rows }   // for ↑/↓
    }

    private func tile(_ window: WindowInfo, metrics: AeroControlMetrics) -> AeroControlAppTile {
        AeroControlAppTile(window: window, metrics: metrics, filtering: filtering)
    }

    @ViewBuilder private var dropTargetHint: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous)
                .fill(palette.accent.opacity(0.12))
                .strokeBorder(palette.accent.opacity(0.9), lineWidth: 3)
        }
    }
}

/// A workspace card's face, the same on the map and in the app strip: the badge at the
/// top-left, the display's name with more than one, the layout's symbol at the top-right,
/// and the pictures in the inner box under them, on the card's fill and hairline.
struct AeroControlCardFace<Content: View>: View {
    let workspace: WorkspaceInfo
    /// The display this workspace lives on; nil with a single display, where naming it is noise.
    let monitorName: String?
    /// The tree was drawn from sizes alone: the shape is right, the places may be swapped.
    let orderUnknown: Bool
    let size: CGSize
    @ViewBuilder let content: () -> Content

    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroDismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }
    private var isFocused: Bool { workspace.name == state.model.focusedWorkspace }
    private var innerSize: CGSize { AeroControlLayout.innerSize(of: size) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous)
        // Same header lane on every card, so the badge sits in the same corner whether the
        // workspace is empty (a narrow card) or full.
        // The tile area gets a fixed frame: a grid that overflowed would otherwise widen the
        // stack and push the badge out of its corner.
        VStack(alignment: .leading, spacing: AeroControlLayout.tileSpacing) {   // air between the badge and the pictures
            header.frame(height: AeroControlLayout.badgeLane - AeroControlLayout.cardPadding)
            content().frame(width: innerSize.width, height: innerSize.height, alignment: .topLeading)
        }
        .padding(AeroControlLayout.cardPadding)
        .frame(width: size.width, height: size.height)
        .background(cardFill(shape))
        .overlay(shape.strokeBorder(palette.cardBorder, lineWidth: 1))   // focus shows on the badge and the window, not the card
        .clipShape(shape)
    }

    /// A solid themed fill, or the platform's frosted glass when the theme is System.
    @ViewBuilder private func cardFill(_ shape: RoundedRectangle) -> some View {
        if let fill = palette.cardFill { shape.fill(fill) } else { shape.fill(.regularMaterial) }
    }

    /// The badge, and with more than one display the name of this workspace's. The tiles
    /// say how many windows there are. The layout symbol fades when the tree is drawn from
    /// sizes alone rather than from AeroSpace's own rects: the shape is right, the places may
    /// be swapped.
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
            if let symbol = AeroControlLayout.layoutSymbol(rootLayout: workspace.rootLayout, windowCount: workspace.windows.count) {
                Image(systemName: symbol.name)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.badgeText.opacity(orderUnknown ? 0.35 : 0.7))
                    .help(orderUnknown ? symbol.help + ". Drawn from the windows' sizes; AeroSpace did not say their order." : symbol.help)
            }
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
            .onTapGesture { state.send(.action(.focusWorkspace(workspace.name))); dismiss() }
            .help(workspace.windows.isEmpty ? "Workspace \(workspace.name)"
                  : "Workspace \(workspace.name) — drag the card onto another workspace to merge")
    }

}
