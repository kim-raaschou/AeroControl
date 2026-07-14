import SwiftUI
import Common

/// A single app within an AeroControl workspace card, styled like the native
/// macOS Cmd-Tab switcher: a clean app icon with a soft drop shadow and no
/// background plate or border. Only the focused app rests on a subtle milky
/// selection plate. The app name sits beneath. Carries tap-to-focus and
/// drag-to-move directly (so it needs no chrome-heavy `WindowIcon`).
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
    /// Icon-plate / focus-ring radius: 8pt at the reference size, scaled down for
    /// smaller icons (never larger).
    private var plateRadius: CGFloat { 8 * min(1, iconSize / AeroControlMetrics.defaultIconSize) }

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

    /// Focus cue, styled like the native macOS Cmd-Tab switcher: a soft, light
    /// translucent rounded rectangle sitting *behind* the icon. It is deliberately
    /// a touch smaller than the icon's frame — it hugs the icon's glyph rather than
    /// the full tile — so that even on a single-app workspace it keeps clear air
    /// from the card's focus border. Drawn at a fixed size relative
    /// to the icon, so showing/hiding focus never reflows the row.
    @ViewBuilder private var selectionPlate: some View {
        if isFocused {
            let side = metrics.focusPlateSize
            let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
            // A genuine Liquid Glass plate, like the macOS Cmd-Tab switcher's
            // selection highlight: `.regular` gives the neutral, appearance-adaptive
            // frost (not a hard white wash) and samples the wallpaper behind the card.
            Color.clear
                .frame(width: side, height: side)
                .glassEffect(.regular, in: shape)
                .overlay {
                    // Lighten the glass toward the macOS Cmd-Tab selection highlight,
                    // which is a bright, light plate rather than a dark frost. A soft
                    // white wash keeps the glass refraction while lifting its tone.
                    shape.fill(plateLighten).allowsHitTesting(false)
                }
        }
    }

    /// A soft white wash layered on the glass so the plate reads as the *light*
    /// Cmd-Tab selection highlight instead of a dark frost over a dark backdrop.
    private var plateLighten: Color {
        colorScheme == .dark ? .white.opacity(0.32) : .white.opacity(0.5)
    }

    /// Floating windows get a subtle dotted outline so they read as "outside the
    /// tiling flow". Appearance-adaptive (light in Dark Mode, soft dark in Light
    /// Mode), sized to hug the icon glyph like the focus plate. Hidden while the
    /// window is focused — the focus plate already carries the emphasis there.
    @ViewBuilder private var floatingHint: some View {
        if window.isFloating && !isFocused {
            // Match the focus plate's footprint exactly, so the floating marker never
            // reaches beyond the plate the focused state would show in its place.
            let side = metrics.focusPlateSize
            let dot = max(1, iconSize * 0.05)
            let gap = iconSize * 0.09
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
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

    /// Solid appearance-adaptive fill for the hover close button — no `.regularMaterial`,
    /// which would stack a second frost on the card's Liquid Glass. Near-opaque so the
    /// primary "xmark" glyph stays legible over any wallpaper.
    private var closeButtonFill: Color {
        colorScheme == .dark ? Color(white: 0.26) : Color(white: 0.92)
    }

    /// A wash that adapts to the system appearance like the macOS Cmd-Tab switcher:
    /// a white overlay in Dark Mode, a black overlay in Light Mode.
    private func adaptive(dark: Double, light: Double) -> Color {
        colorScheme == .dark ? .white.opacity(dark) : .black.opacity(light)
    }

    /// Hover affordance: a small close button in the tile's top-trailing corner
    /// (top-leading is reserved for the workspace badge on the first tile). Wrapped
    /// in a `Button` so its tap is consumed and never falls through to the tile's
    /// focus gesture. Closes the window gracefully via `aerospace close`.
    @ViewBuilder private var closeButton: some View {
        if isHovering {
            // The *visible* circle scales proportionally with the icon (~⅓ of it at
            // every size), so it never dominates a small icon. The hit area is exactly
            // the visible circle — no invisible enlarged frame — so a click only closes
            // when it lands on the X you can actually see; every other click on the
            // icon falls through to tap-to-focus.
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
