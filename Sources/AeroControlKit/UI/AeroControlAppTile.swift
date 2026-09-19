import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroDismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme
    @Environment(\.aeroMotion) private var motion

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }
    let window: WindowInfo
    let metrics: AeroControlMetrics
    /// Whether the grid this tile sits in is a filtered result. The panel decides that once,
    /// from what it is drawing — a second answer derived from the query length disagreed with
    /// it on a miss, and captioned every window on a map that had not moved.
    let filtering: Bool

    @State private var isHovering = false

    /// The window's snapshot, fitted into the cell with its own aspect ratio; until it lands
    /// — or for good, without Screen Recording — the tile is a plate in the snapshot's shape.
    /// No icons: they said nothing a picture and a title do not, and flashed in whenever a
    /// picture went away.
    private var preview: NSImage? { state.previews[window.windowId] }
    /// The ring: AeroSpace's focus on the map, the selected match while filtering.
    private var isFocused: Bool { window.windowId == state.ringWindowId }

    /// While a filter is up the title is the point: two windows of one app are told apart by
    /// their title and their picture, and the title is the one that is provably current —
    /// AeroSpace re-reads it from Accessibility on every load. It is drawn rather than left
    /// in the tooltip, which costs a second of holding the mouse still.
    private var showsCaption: Bool {
        filtering && tileSize.height >= AeroControlLayout.captionLane + Self.minPictureHeight
    }

    /// A window without a title is still a window; name it by its app rather than leave the
    /// caption blank.
    private var captionText: String { window.title.isEmpty ? window.appName : window.title }

    /// A caption only earns its lane when the picture under it stays at least this tall;
    /// below that the label would be bigger than the thing it labels.
    private static let minPictureHeight: CGFloat = 92

    private func onFocusWindow() {
        state.send(.action(.focusWindow(window.windowId)))
        dismiss()
    }

    private func onCloseWindow() {
        state.send(.action(.closeWindow(window.windowId)))
    }

    /// Pointing is the selection: Cmd-Q acts on whatever the mouse is over.
    private func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        if hovering { state.hoveredWindowId = window.windowId }
        else if state.hoveredWindowId == window.windowId { state.hoveredWindowId = nil }
    }
    private var cellPadding: CGFloat { metrics.tileCellPadding }
    private var plateRadius: CGFloat { AeroControlMetrics.snapshotRadius }
    /// The focus ring follows the content radius plus its gap.
    private var ringRadius: CGFloat { plateRadius + AeroControlMetrics.snapshotRingGap }
    private var tileSize: CGSize { metrics.tileSize }

    /// The room the picture has: the cell, less the caption's lane when there is one. Every
    /// other size here is derived from this one box, so the ring, the close button and the
    /// picture can never disagree about where the picture is.
    private var pictureBox: CGSize {
        CGSize(width: tileSize.width,
               height: tileSize.height - (showsCaption ? AeroControlLayout.captionLane : 0))
    }

    /// What is actually drawn: the fitted snapshot — sized from the window's measured size
    /// before the picture is in, so the place it lands in is already its shape — or the
    /// whole box when nothing is known about the window.
    private var contentSize: CGSize {
        guard let size = preview?.size ?? state.previewSizes[window.windowId] else { return pictureBox }
        return AeroControlMetrics.fit(size, into: pictureBox)
    }

    /// The focus frame hugs the drawn content, not the cell.
    private var plateSize: CGSize { AeroControlMetrics.focusPlateRect(around: contentSize) }

    var body: some View {
        VStack(spacing: AeroControlLayout.captionGap) {
            if showsCaption { caption }
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
    private var caption: some View {
        Text(captionText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.badgeText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(height: AeroControlLayout.captionTitleHeight)
    }

    /// The picture, its focus ring and the close button — everything the caption is not.
    private var artwork: some View {
        tile
            .frame(width: contentSize.width, height: contentSize.height)
            .animation(.easeOut(duration: 0.15 * motion), value: preview == nil)   // the picture fades into its place as it lands
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.offset)
            .overlay(alignment: .topTrailing) { closeButton }
            .background(selectionPlate)
    }

    @ViewBuilder private var tile: some View {
        if let preview {
            Image(nsImage: preview)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: plateRadius, style: .continuous))
                .transition(.opacity)
        } else {
            RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
                .fill(palette.badgeFill.opacity(0.35))
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
            let diameter: CGFloat = 18
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
            .padding(6)                                         // inside the snapshot's corner, clear of the focus ring
            .help("Close window")
        }
    }
}
