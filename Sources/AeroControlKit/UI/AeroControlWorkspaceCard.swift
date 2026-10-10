import SwiftUI
import Common

struct AeroControlWorkspaceCard: View {
    let card: OverviewScene.Card
    let tiles: Namespace.ID
    private var workspace: WorkspaceInfo { card.workspace }
    private var size: CGSize { card.frame.size }

    @State private var isDropTarget = false
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous)
        AeroControlCardFace(card: card) {
            grid()
        }
        .overlay(dropTargetHint.allowsHitTesting(false))
        .overlay(shape.strokeBorder(look.palette.accent, lineWidth: AeroControlMetrics.focusRingWidth(scale: displayScale)).opacity(card.ringed ? 1 : 0))
        .contentShape(shape)
        .onTapGesture { state.send(.action(.focusWorkspace(workspace.name))) }
        .draggable(OverviewDragPayload.workspace(name: workspace.name)) { dragPreview }
        .dropDestination(for: OverviewDragPayload.self) { items, _ in
            guard let item = items.first else { return false }
            isDropTarget = false
            switch item {
            case .window(let id):
                guard !workspace.windows.contains(where: { $0.windowId == id }) else { return false }
                state.send(.action(.moveWindow(windowId: id, toWorkspace: workspace.name)))
            case .workspace(let source):
                guard source != workspace.name else { return false }
                state.send(.action(.mergeWorkspace(source: source, into: workspace.name)))
            }
            return true
        } isTargeted: { isDropTarget = $0 }
    }

    private var dragPreview: some View {
        Text(workspace.name)
            .font(.system(size: 17, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(look.palette.focusedBadgeText)
            .frame(width: 32, height: 32)
            .background(look.palette.accent, in: Circle())
            .padding(6)
    }

    private func grid() -> some View {
        let inner = AeroControlLayout.inner(of: size)
        return ZStack(alignment: .topLeading) {
            ForEach(card.tiles, id: \.window.windowId) { tile in
                AeroControlAppTile(tile: tile, tiles: tiles)
                    .onHover { if $0 { state.point(tile.window.windowId, at: NSEvent.mouseLocation) } }
                    .offset(x: tile.frame.minX, y: tile.frame.minY)
                    .opacity(tile.ghost ? 0.7 : 1)
                    .zIndex(tile.stacking)
            }
        }
        .frame(width: inner.width, height: inner.height, alignment: .topLeading)
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

struct AeroControlCardFace<Content: View>: View {
    let card: OverviewScene.Card
    @ViewBuilder let content: () -> Content

    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look

    private var workspace: WorkspaceInfo { card.workspace }
    private var size: CGSize { card.frame.size }
    private var isFocused: Bool { card.focused }
    private var monitorName: String? { card.monitor }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: AeroControlLayout.tileSpacing) {
            header.frame(height: AeroControlLayout.badgeLane - AeroControlLayout.cardPadding)
            let inner = AeroControlLayout.inner(of: size)
            content().frame(width: inner.width, height: inner.height, alignment: .topLeading)
        }
        .padding(AeroControlLayout.cardPadding)
        .frame(width: size.width, height: size.height)
        .background(cardFill(shape))
        .overlay(shape.strokeBorder(look.palette.cardBorder, lineWidth: 1))
        .clipShape(shape)
    }

    private func cardFill(_ shape: RoundedRectangle) -> some View {
        ZStack {
            if look.surface == .strip { shape.fill(.ultraThickMaterial) }
            if let fill = look.palette.cardFill { shape.fill(fill) } else { shape.fill(.regularMaterial) }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            badge
            if let monitorName {
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
