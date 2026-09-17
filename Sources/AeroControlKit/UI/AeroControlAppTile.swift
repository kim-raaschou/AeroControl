import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }
    let window: WindowInfo
    let image: NSImage?
    /// Window snapshot; when present the tile is the bare snapshot, fitted into the 3:2 cell
    /// with its own aspect ratio and the app icon badged in its corner, otherwise the app icon.
    let preview: NSImage?
    let isFocused: Bool
    let onFocusWindow: () -> Void
    let onCloseWindow: () -> Void
    let onHoverChanged: (Bool) -> Void

    @State private var isHovering = false

    let metrics: AeroControlMetrics
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

    init(
        window: WindowInfo,
        image: NSImage?,
        preview: NSImage? = nil,
        isFocused: Bool,
        onFocusWindow: @escaping () -> Void,
        onCloseWindow: @escaping () -> Void = {},
        onHoverChanged: @escaping (Bool) -> Void = { _ in },
        metrics: AeroControlMetrics = AeroControlMetrics(iconSize: 32)
    ) {
        self.window = window
        self.image = image
        self.preview = preview
        self.isFocused = isFocused
        self.onFocusWindow = onFocusWindow
        self.onCloseWindow = onCloseWindow
        self.onHoverChanged = onHoverChanged
        self.metrics = metrics
    }

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
        tile
            .frame(width: contentSize.width, height: contentSize.height)
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.offset)
            .overlay(alignment: .topTrailing) { closeButton }
            .frame(width: tileSize.width, height: tileSize.height)
            .padding(cellPadding)
            .background(selectionPlate)
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocusWindow)
            .onHover { isHovering = $0; onHoverChanged($0) }
            .help(window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)")
            .draggable(OverviewDragPayload.window(id: window.windowId)) {
                tile
                    .frame(width: contentSize.width, height: contentSize.height)
                    .onAppear { isHovering = false; onHoverChanged(false) }
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
