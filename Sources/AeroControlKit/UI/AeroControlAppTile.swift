import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(\.colorScheme) private var colorScheme
    let window: WindowInfo
    let image: NSImage?
    let isFocused: Bool
    let onFocusWindow: () -> Void
    let onCloseWindow: () -> Void

    @State private var isHovering = false

    let iconSize: CGFloat
    private var metrics: AeroControlMetrics { AeroControlMetrics(iconSize: iconSize) }
    private var cellPadding: CGFloat { metrics.tileCellPadding }
    private var plateRadius: CGFloat { metrics.iconArtworkRadius }

    init(
        window: WindowInfo,
        image: NSImage?,
        isFocused: Bool,
        onFocusWindow: @escaping () -> Void,
        onCloseWindow: @escaping () -> Void = {},
        iconSize: CGFloat = 32
    ) {
        self.window = window
        self.image = image
        self.isFocused = isFocused
        self.onFocusWindow = onFocusWindow
        self.onCloseWindow = onCloseWindow
        self.iconSize = iconSize
    }

    var body: some View {
        icon
            .frame(width: iconSize, height: iconSize)
            .shadow(color: .black.opacity(isFocused ? 0 : 0.12), radius: 2, y: 1)
            .overlay(alignment: .topTrailing) { closeButton }
            .padding(cellPadding)
            .background(selectionPlate)
            .overlay(floatingHint)
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocusWindow)
            .onHover { isHovering = $0 }
            .draggable(WindowDragData(windowId: window.windowId, appName: window.appName)) {
                icon
                    .frame(width: iconSize, height: iconSize)
                    .onAppear { isHovering = false }
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
            let side = metrics.focusPlateSize
            let shape = RoundedRectangle(cornerRadius: metrics.focusPlateRadius, style: .continuous)
            shape
                .fill(.regularMaterial)
                .overlay { shape.fill(plateLighten) }
                .frame(width: side, height: side)
        }
    }

    private var plateLighten: Color {
        colorScheme == .dark ? .white.opacity(0.18) : .white.opacity(0.30)
    }

    @ViewBuilder private var floatingHint: some View {
        if window.isFloating && !isFocused {
            let side = metrics.focusPlateSize
            let dot = max(1, iconSize * 0.05)
            let gap = iconSize * 0.09
            RoundedRectangle(cornerRadius: metrics.focusPlateRadius, style: .continuous)
                .strokeBorder(
                    floatingStroke,
                    style: StrokeStyle(lineWidth: dot, lineCap: .round, dash: [0.01, gap])
                )
                .frame(width: side, height: side)
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
