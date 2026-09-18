import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroDismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }
    let window: WindowInfo
    let metrics: AeroControlMetrics
    /// The digit that picks this tile while a filter is up; nil when it was not numbered.
    let ordinal: Int?

    @State private var isHovering = false

    private var image: NSImage? { state.icons[window.windowId] }
    /// Window snapshot; when present the tile is the bare snapshot, fitted into the 3:2 cell
    /// with its own aspect ratio and the app icon badged in its corner, otherwise the app icon.
    private var preview: NSImage? { state.previews[window.windowId] }
    private var isFocused: Bool { window.windowId == state.model.focusedWindowId }

    /// While a filter is up the title is the point: two windows of one app are told apart by
    /// their title and their picture, and the title is the one that is provably current —
    /// AeroSpace re-reads it from Accessibility on every load. It is drawn rather than left
    /// in the tooltip, which costs a second of holding the mouse still.
    private var showsTitle: Bool {
        state.isFiltering && !window.title.isEmpty && tileSize.height >= Self.minTitledTileHeight
    }

    /// Below this the title would take more of the cell than the picture it labels.
    private static let minTitledTileHeight: CGFloat = 130
    private static let titleLane: CGFloat = 32

    private func onFocusWindow() {
        Task { [weak state] in await state?.dispatch(.focusWindow(window.windowId)) }
        dismiss()
    }

    private func onCloseWindow() {
        Task { [weak state] in await state?.dispatch(.closeWindow(window.windowId)) }
    }

    /// Pointing is the selection: Cmd-Q acts on whatever the mouse is over.
    private func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        if hovering { state.hoveredWindowId = window.windowId }
        else if state.hoveredWindowId == window.windowId { state.hoveredWindowId = nil }
    }
    private var iconSize: CGFloat { metrics.iconSize }
    private var cellPadding: CGFloat { metrics.tileCellPadding }
    /// Corner radius of the drawn content: gentle on snapshots, the icon's own on icons.
    private var plateRadius: CGFloat {
        metrics.previews ? AeroControlMetrics.snapshotRadius : metrics.iconArtworkRadius
    }
    /// The focus ring follows the content radius plus its gap.
    private var ringRadius: CGFloat {
        plateRadius + (metrics.previews ? AeroControlMetrics.snapshotRingGap : metrics.focusPlatePadding)
    }
    private var tileSize: CGSize { metrics.tileSize }

    /// What is actually drawn: the fitted snapshot, or the whole cell for icons.
    private var contentSize: CGSize {
        guard metrics.previews else { return tileSize }
        guard let preview else { return CGSize(width: tileSize.height, height: tileSize.height) }
        return metrics.fittedPreviewSize(preview.size)
    }

    /// The focus frame hugs the drawn content, not the cell.
    private var plateSize: CGSize {
        metrics.previews ? metrics.focusPlateRect(around: contentSize) : metrics.focusPlateRect
    }

    var body: some View {
        VStack(spacing: 6) {
            if showsTitle { titleLabel }
            artwork
        }
            .frame(width: tileSize.width, height: tileSize.height)
            .padding(cellPadding)
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocusWindow)
            .onHover(perform: hoverChanged)
            .help(window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)")
            .draggable(OverviewDragPayload.window(id: window.windowId)) {
                tile
                    .frame(width: contentSize.width, height: contentSize.height)
                    .onAppear { hoverChanged(false) }
            }
    }

    /// The window's own name, centred over the picture it belongs to. Never truncated: a
    /// filter that has narrowed to a handful leaves each tile wide, and the part that tells
    /// two windows apart sits at the front of the title where an ellipsis would land.
    private var titleLabel: some View {
        Text(window.title)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.badgeText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(height: Self.titleLane)
    }

    /// The picture, its focus ring and the two corner affordances — everything the title is
    /// not, so the ring keeps hugging the snapshot when a caption appears above it.
    private var artwork: some View {
        tile
            .frame(width: contentSize.width, height: artworkHeight)
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.offset)
            .overlay(alignment: .topLeading) { ordinalBadge }
            .overlay(alignment: .topTrailing) { closeButton }
            .background(selectionPlate)
    }

    /// A caption never pushes the card open: it takes its lane out of the cell, not out of
    /// the picture. Most snapshots are limited by the cell's width and leave height to spare,
    /// so the usual case costs the picture nothing at all.
    private var artworkHeight: CGFloat {
        guard showsTitle else { return contentSize.height }
        return min(contentSize.height, tileSize.height - Self.titleLane - 6)
    }

    /// The keystroke that picks this match, drawn as a keycap so it reads as a shortcut and
    /// not as the round accent circle a workspace badge is.
    @ViewBuilder private var ordinalBadge: some View {
        if let ordinal {
            Text("\(ordinal)")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(palette.accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(palette.badgeFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .padding(4)
        }
    }

    @ViewBuilder private var tile: some View {
        if metrics.previews, let preview {
            Image(nsImage: preview)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: plateRadius, style: .continuous))
                .overlay(alignment: .bottomLeading) {       // the badge is not clipped with the image
                    icon
                        .frame(width: metrics.previewBadgeSize, height: metrics.previewBadgeSize)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .padding(metrics.previewBadgeSize * 0.2)
                }
        } else {
            icon
        }
    }

    @ViewBuilder private var icon: some View {
        if let image {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: plateRadius)
                .fill(.quaternary)
                .overlay { Image(systemName: "app.fill").foregroundStyle(.secondary) }
        }
    }

    /// Focus: a thin accent ring with a small gap around the drawn content and a soft glow,
    /// matching the focused workspace card's accent border.
    /// A floating window is not in the tiling layout: it lies on top of it. The map already
    /// draws it there, so the tile only has to look raised — a real shadow, no extra outline
    /// competing with the focus ring. Focused floating windows keep both.
    private var shadow: (opacity: Double, radius: CGFloat, offset: CGFloat) {
        if window.isFloating { return (0.5, 12, 5) }
        return (isFocused ? 0 : 0.12, 2, 1)
    }

    @ViewBuilder private var selectionPlate: some View {
        if isFocused {
            let size = plateSize
            let shape = RoundedRectangle(cornerRadius: ringRadius, style: .continuous)
            shape
                .strokeBorder(palette.accent, lineWidth: AeroControlMetrics.focusRingWidth)
                .shadow(color: palette.accent.opacity(0.5), radius: 4)
                .frame(width: size.width, height: size.height)
        }
    }

    @ViewBuilder private var closeButton: some View {
        if isHovering {
            let diameter: CGFloat = metrics.previews ? 18 : max(11, iconSize * 0.32)
            Button(action: onCloseWindow) {
                Image(systemName: "xmark")
                    .font(.system(size: diameter * 0.45, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: diameter, height: diameter)
                    .background(palette.closeButtonFill, in: Circle())
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(metrics.previews ? 6 : 0)                  // inside the snapshot's corner, clear of the focus ring
            .offset(x: metrics.previews ? 0 : diameter * 0.15, y: metrics.previews ? 0 : -diameter * 0.15)
            .help("Close window")
        }
    }
}
