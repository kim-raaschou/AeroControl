import SwiftUI
import Common

/// One "desktop" card: badge at the top-left, the workspace's windows below as a grid of
/// snapshot cells.
/// Drop target for window tiles (move) and workspace cards (merge).
struct AeroControlWorkspaceCard: View {
    let workspace: WorkspaceInfo
    /// The card as the map laid it out: its cell, and every window where it is drawn in it.
    let card: AeroControlLayout.MapCard
    /// Whether this card is part of a filtered result rather than the map.
    let filtering: Bool
    /// The panel's namespace for the tiles (`AeroControlPanel.tiles`).
    let tiles: Namespace.ID
    private var size: CGSize { card.frame.size }

    @State private var isDropTarget = false
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous)
        AeroControlCardFace(workspace: workspace, size: size) {
            grid()
        }
        .overlay(dropTargetHint.allowsHitTesting(false))
        // An empty workspace the keys are on wears the ring itself: Enter switches to it.
        .overlay(shape.strokeBorder(look.palette.accent, lineWidth: AeroControlMetrics.focusRingWidth(scale: displayScale)).opacity(state.markedWorkspace == workspace.name ? 1 : 0))
        .contentShape(shape)
        .onTapGesture { state.send(.action(.focusWorkspace(workspace.name))) }
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
                state.send(.action(.moveWindow(windowId: id, toWorkspace: workspace.name)))
            case .workspace(let source):
                guard source != workspace.name else { return false }
                state.send(.action(.mergeWorkspace(source: source, into: workspace.name)))
            }
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    /// What follows the cursor while a workspace is dragged: its badge, a little larger.
    private var dragPreview: some View {
        Text(workspace.name)
            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(look.palette.focusedBadgeText)
            .frame(width: 32, height: 32)
            .background(look.palette.accent, in: Circle())
            .padding(6)
    }

    private func grid() -> some View {
        let windows = workspace.windows
        let inner = AeroControlLayout.inner(of: size)
        return ZStack(alignment: .topLeading) {
            ForEach(windows, id: \.windowId) { window in
                let frame = card.frames[window.windowId] ?? .zero
                let ghost = card.ghosts.contains(window.windowId)
                AeroControlAppTile(window: window, size: frame.size, filtering: filtering, tiles: tiles)
                    .onHover { if $0 { state.point(window.windowId, at: NSEvent.mouseLocation) } }
                    .offset(x: frame.minX, y: frame.minY)
                    .opacity(ghost ? 0.7 : 1)          // see-through, as krn.overview draws a float: what lies under it shows
                    .zIndex(AeroControlLayout.stacking(windowId: window.windowId, focused: state.model.focusedWindowId, ghosts: card.ghosts))
            }
        }
        .frame(width: inner.width, height: inner.height, alignment: .topLeading)
        // The card as laid out, frames included: a window settling into its size moves, not snaps.
        .animation(.easeInOut(duration: 0.15 * look.motion), value: card)
    }

    @ViewBuilder private var dropTargetHint: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous)
                .fill(look.palette.accent.opacity(0.12))
                .strokeBorder(look.palette.accent.opacity(0.9), lineWidth: 3)
        }
    }
}

/// A workspace card's face, the same on the map and in the app strip: the badge at the
/// top-left, the display's name with more than one, the layout's symbol at the top-right,
/// and the pictures in the inner box under them, on the card's fill and hairline.
struct AeroControlCardFace<Content: View>: View {
    let workspace: WorkspaceInfo
    let size: CGSize
    @ViewBuilder let content: () -> Content

    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look

    private var isFocused: Bool { workspace.name == state.model.focusedWorkspace }
    /// The display this workspace lives on; nil with a single display, where naming it is noise.
    private var monitorName: String? { state.model.spansMonitors ? workspace.monitorShortName : nil }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous)
        // Same header lane on every card, so the badge sits in the same corner whether the
        // workspace is empty (a narrow card) or full.
        // The tile area gets a fixed frame: a grid that overflowed would otherwise widen the
        // stack and push the badge out of its corner.
        VStack(alignment: .leading, spacing: AeroControlLayout.tileSpacing) {   // air between the badge and the pictures
            header.frame(height: AeroControlLayout.badgeLane - AeroControlLayout.cardPadding)
            let inner = AeroControlLayout.inner(of: size)
            content().frame(width: inner.width, height: inner.height, alignment: .topLeading)
        }
        .padding(AeroControlLayout.cardPadding)
        .frame(width: size.width, height: size.height)
        .background(cardFill(shape))
        .overlay(shape.strokeBorder(look.palette.cardBorder, lineWidth: 1))   // focus shows on the badge and the window, not the card
        .clipShape(shape)
    }

    /// A solid themed fill, or the platform's frosted glass when the theme is System.
    /// Over the bare desktop, in the strip, it lies on a thick frost as ⌘Tab's panel does, so nothing behind reads through.
    private func cardFill(_ shape: RoundedRectangle) -> some View {
        ZStack {
            if look.surface == .strip { shape.fill(.ultraThickMaterial) }
            if let fill = look.palette.cardFill { shape.fill(fill) } else { shape.fill(.regularMaterial) }
        }
    }

    /// The badge, and with more than one display the name of this workspace's. The tiles
    /// say how many windows there are; the layout symbol says how AeroSpace arranges them.
    private var header: some View {
        HStack(spacing: 6) {
            badge
            if let monitorName, !monitorName.isEmpty {
                Label(monitorName, systemImage: "display")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(look.palette.badgeText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
            if let symbol = AeroControlLayout.layoutSymbol(rootLayout: workspace.rootLayout) {
                Image(systemName: symbol.name)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(look.palette.badgeText.opacity(0.7))
                    .help(symbol.help)
            }
        }
    }

    /// The workspace name as a quiet monogram: a filled circle with no outline, in the
    /// accent color for the focused workspace and a faint tint otherwise.
    private var badge: some View {
        Text(workspace.name)
            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
            .lineLimit(1)
            .foregroundStyle(isFocused ? look.palette.focusedBadgeText : look.palette.badgeText)
            .frame(width: AeroControlLayout.badgeSize, height: AeroControlLayout.badgeSize)
            .background(isFocused ? look.palette.accent : look.palette.badgeFill, in: Circle())
            .contentShape(Circle())
            .onTapGesture { state.send(.action(.focusWorkspace(workspace.name))) }
            .help(workspace.windows.isEmpty ? "Workspace \(workspace.name)"
                  : "Workspace \(workspace.name) — drag the card onto another workspace to merge")
    }

}
