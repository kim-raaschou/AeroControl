import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let window: WindowInfo
    let image: NSImage?
    /// Window snapshot; when present the tile is a 3:2 preview with the app icon badged
    /// in its corner, otherwise the plain app icon.
    let preview: NSImage?
    let isFocused: Bool
    let onFocusWindow: () -> Void
    let onCloseWindow: () -> Void

    @State private var isHovering = false

    let metrics: AeroControlMetrics
    private var iconSize: CGFloat { metrics.iconSize }
    private var cellPadding: CGFloat { metrics.tileCellPadding }
    private var plateRadius: CGFloat { metrics.iconArtworkRadius }
    private var tileSize: CGSize { metrics.tileSize }

    init(
        window: WindowInfo,
        image: NSImage?,
        preview: NSImage? = nil,
        isFocused: Bool,
        onFocusWindow: @escaping () -> Void,
        onCloseWindow: @escaping () -> Void = {},
        metrics: AeroControlMetrics = AeroControlMetrics(iconSize: 32)
    ) {
        self.window = window
        self.image = image
        self.preview = preview
        self.isFocused = isFocused
        self.onFocusWindow = onFocusWindow
        self.onCloseWindow = onCloseWindow
        self.metrics = metrics
    }

    var body: some View {
        tile
            .frame(width: tileSize.width, height: tileSize.height)
            .shadow(color: .black.opacity(isFocused ? 0 : 0.12), radius: 2, y: 1)
            .overlay(alignment: .topTrailing) { closeButton }
            .padding(cellPadding)
            .background(selectionPlate)
            .overlay(floatingHint)
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocusWindow)
            .onHover { isHovering = $0 }
            .help(window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)")
            .draggable(OverviewDragPayload.window(id: window.windowId)) {
                tile
                    .frame(width: tileSize.width, height: tileSize.height)
                    .onAppear { isHovering = false }
            }
    }

    @ViewBuilder private var tile: some View {
        if metrics.previews {
            let shape = RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
            ZStack(alignment: .bottomLeading) {
                shape.fill(.quaternary)
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: tileSize.width, height: tileSize.height)
                }
                icon
                    .frame(width: metrics.previewBadgeSize, height: metrics.previewBadgeSize)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(metrics.previewBadgeSize * 0.2)
            }
            .clipShape(shape)
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

    @ViewBuilder private var selectionPlate: some View {
        if isFocused {
            let size = metrics.focusPlateRect
            let shape = RoundedRectangle(cornerRadius: metrics.focusPlateRadius, style: .continuous)
            shape
                .fill(.regularMaterial)
                .overlay { shape.fill(plateLighten) }
                .frame(width: size.width, height: size.height)
        }
    }

    private var plateLighten: Color {
        colorScheme == .dark ? .white.opacity(0.18) : .white.opacity(0.30)
    }

    @ViewBuilder private var floatingHint: some View {
        if window.isFloating && !isFocused {
            let size = metrics.focusPlateRect
            let dot = max(1, iconSize * 0.05)
            let gap = iconSize * 0.09
            RoundedRectangle(cornerRadius: metrics.focusPlateRadius, style: .continuous)
                .strokeBorder(
                    floatingStroke,
                    style: StrokeStyle(lineWidth: dot, lineCap: .round, dash: [0.01, gap])
                )
                .frame(width: size.width, height: size.height)
        }
    }

    private var floatingStroke: Color {
        adaptive(dark: 0.33, light: 0.23)
    }

    private var closeButtonFill: Color {
        colorScheme == .dark ? Color(white: 0.26) : Color(white: 0.92)
    }

    private func adaptive(dark: Double, light: Double) -> Color {
        colorScheme == .dark ? .white.opacity(dark) : .black.opacity(light)
    }

    @ViewBuilder private var closeButton: some View {
        if isHovering {
            let diameter = max(11, iconSize * 0.32)
            Button(action: onCloseWindow) {
                Image(systemName: "xmark")
                    .font(.system(size: diameter * 0.45, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: diameter, height: diameter)
                    .background(closeButtonFill, in: Circle())
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .offset(x: diameter * 0.15, y: -diameter * 0.15)
            .help("Close window")
        }
    }
}
