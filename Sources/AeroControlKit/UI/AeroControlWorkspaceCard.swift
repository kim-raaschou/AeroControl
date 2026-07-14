import SwiftUI
import Common

/// A workspace in the AeroControl overview: a Liquid Glass card filling the
/// width/height handed to it by the panel (equal height across workspaces;
/// width scales with app count). Non-empty cards show the workspace name and a
/// grid of clean native-style app icons; empty cards show the name with a clear,
/// visible placeholder (not a faint sliver). Subtle accordion framing hint;
/// drop target for moving windows.
struct AeroControlWorkspaceCard: View {
    let workspace: WorkspaceInfo
    let isFocused: Bool
    let focusedWindowId: Int
    let icons: [Int: NSImage]
    let iconSize: CGFloat
    let onFocusWorkspace: () -> Void
    let onFocusWindow: (Int) -> Void
    let onMoveWindow: (Int, String) -> Void
    let onCloseWindow: (Int) -> Void
    /// When true the strip runs vertically (a left/right dock edge): the app icons
    /// stack top-to-bottom instead of left-to-right.
    var isVertical: Bool = false

    @State private var isDropTarget = false
    @Environment(\.colorScheme) private var colorScheme

    /// Dynamic Type factor for the strip's small labels. A unit `@ScaledMetric`
    /// relative to `.caption` yields the user's text-size multiplier; we scale the
    /// icon-derived font sizes by it (clamped) so labels honor Accessibility text
    /// sizes without overflowing the fixed-height strip.
    @ScaledMetric(relativeTo: .caption) private var typeScale: CGFloat = 1
    private var clampedTypeScale: CGFloat { min(max(typeScale, 1), 1.5) }

    private var metrics: AeroControlMetrics { AeroControlMetrics(iconSize: iconSize) }
    private var cornerRadius: CGFloat { metrics.cornerRadius }

    var body: some View {
        content
            .dropDestination(for: WindowDragData.self) { items, _ in
                guard let item = items.first else { return false }
                isDropTarget = false
                onMoveWindow(item.windowId, workspace.name)
                return true
            } isTargeted: { isDropTarget = $0 }
    }

    @ViewBuilder private var content: some View {
        if workspace.windows.isEmpty {
            emptyPill
        } else {
            cardContent
        }
    }

    /// Empty workspaces: like Cmd-Tab, only the focused one gets a glass plate. A
    /// non-focused empty workspace is just its name badge (no container).
    private var emptyPill: some View {
        withFocusPlate {
            if isVertical {
                Color.clear
                    .frame(height: metrics.emptyCardWidth)
                    .frame(maxWidth: .infinity)
            } else {
                Color.clear
                    .frame(width: metrics.emptyCardWidth)
                    .frame(maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocusWorkspace)
    }

    /// Applies the shared card chrome. The badge is drawn as an `.overlay` on the
    /// card content *before* the glass modifier, so it becomes the glass view's own
    /// content — which `glassEffect(_:in:)` guarantees renders *above* the glass
    /// shape (Apple "Applying Liquid Glass to custom views", Pattern A). This keeps
    /// the badge visible even when the whole row is wrapped in a `GlassEffectContainer`
    /// (where a plain non-glass sibling would get composited into the shared glass
    /// pass and vanish). The badge also avoids `.ultraThinMaterial` — Apple warns
    /// against material-on-glass; it uses a solid vibrant fill instead.
    @ViewBuilder private func withFocusPlate(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .overlay(alignment: .topLeading) { badge.allowsHitTesting(false) }
            .modifier(FocusPlate(isFocused: isFocused, cornerRadius: cornerRadius))
            .overlay(dropTargetHint.allowsHitTesting(false))
    }

    private var cardContent: some View {
        withFocusPlate {
            appRow
                .padding(.top, metrics.cardTopPadding)
                .padding(.bottom, metrics.cardBottomPadding)
                .padding(.horizontal, metrics.cardHorizontalPadding)
                .frame(
                    maxWidth: isVertical ? .infinity : nil,
                    maxHeight: isVertical ? nil : .infinity,
                    alignment: isVertical ? .leading : .top
                )
                // Workspace-focus tap lives on a background layer *behind* the app row.
                // SwiftUI hit-tests front-to-back, so taps on an icon hit the tile
                // (window focus) and only taps in the gaps/empty area fall through here
                // (workspace focus). This avoids parent/child tap-priority ambiguity.
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onFocusWorkspace)
                }
        }
    }

    /// The workspace name as a compact corner badge (replaces the old header row,
    /// so it costs no layout height). Text colour follows the system appearance and
    /// sits on a material capsule so it stays legible over any wallpaper.
    private var badge: some View {
        Text(workspace.name)
            .font(.system(size: metrics.badgeFontSize * clampedTypeScale, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.18), radius: 1.5, x: 0, y: 0.5)
            .padding(.horizontal, metrics.badgePaddingH)
            .padding(.vertical, metrics.badgePaddingV)
            .background(badgeFill, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    .white.opacity(colorScheme == .dark ? 0.25 : 0.4),
                    lineWidth: 1
                )
            )
            .padding(.leading, metrics.badgeInset)
            .padding(.top, metrics.badgeInset)
    }

    /// A solid vibrant capsule fill instead of `.ultraThinMaterial`: Apple's Liquid
    /// Glass guidance is to avoid stacking material on glass and use fills/vibrancy
    /// for elements sitting on glass. A stronger appearance-adaptive wash keeps the
    /// badge crisply legible over the frosted card without a second backdrop layer.
    private var badgeFill: Color {
        colorScheme == .dark ? .black.opacity(0.45) : .white.opacity(0.72)
    }

    /// All apps in one line; the card sizes to fit them, so nothing scrolls. The line
    /// runs horizontally for top/bottom strips and vertically for left/right strips.
    private var appRow: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.appRowSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: metrics.appRowSpacing))
        return layout {
            ForEach(workspace.windows, id: \.windowId) { window in
                AeroControlAppTile(
                    window: window,
                    image: icons[window.windowId],
                    isFocused: window.windowId == focusedWindowId,
                    onFocusWindow: { onFocusWindow(window.windowId) },
                    onCloseWindow: { onCloseWindow(window.windowId) },
                    iconSize: iconSize
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: workspace.windows)
    }

    @ViewBuilder private var dropTargetHint: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
        }
    }
}

/// The glass treatment for a workspace, modelled on the macOS Cmd-Tab switcher
/// panel: every workspace gets a *frosted* `.regular` Liquid Glass panel (frosted,
/// not clear — clear leans entirely on the bevel rim to stay visible, which reads
/// as a harsh dark edge over dark wallpaper, especially on 1x displays). The
/// FOCUSED workspace gets the same frosted glass with a light accent tint for the
/// Cmd-Tab-style selection — a single glass edge, no manual fill, no drawn border.
private struct FocusPlate: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            // Accessibility: no backdrop-sampling glass. Fall back to an opaque plate
            // so cards stay legible when the system disables transparency — focused
            // gets an accent-tinted plate, the rest a neutral appearance-adaptive one.
            content
                .background {
                    shape
                        .fill(opaqueBase)
                        .overlay { if isFocused { shape.fill(Color.accentColor.opacity(0.5)) } }
                }
        } else {
            // Clear Liquid Glass gives the transparent card its subtle refraction —
            // the desktop reads straight through the centre while the rim lenses/warps
            // the wallpaper (the "distorted glass" look). A single crisp hairline sits
            // on top for a defined, "crispy" edge; focus tints that edge accent-blue
            // (no fill change, so all workspaces keep the same transparency).
            content
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    // A uniform, whisper-thin frost — the "in-between" between bare
                    // `.clear` (almost no body) and `.regular` (heavy, backdrop-adaptive
                    // frost). Uniform across all workspaces; the focused one is marked
                    // by its edge (and by the app selection plate), not a coloured wash.
                    shape.fill(frostBody).allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(
                        isFocused ? Color.accentColor.opacity(0.95) : crispEdge,
                        lineWidth: isFocused ? 1.75 : 1.25
                    )
                    .allowsHitTesting(false)
                }
        }
    }

    /// The "in-between" body: a fixed, appearance-adaptive milky wash that gives the
    /// clear glass a little more presence without the heavy, uneven `.regular` frost.
    private var frostBody: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.12)
    }

    /// A single crisp hairline that gives each clear-glass card a defined, "crispy"
    /// panel edge — appearance-adaptive so it reads on any wallpaper.
    private var crispEdge: Color {
        colorScheme == .dark ? .white.opacity(0.45) : .white.opacity(0.65)
    }

    /// Opaque base plate colour used only when Reduce Transparency is on. The focused
    /// card layers the accent over this base so it still reads as selected.
    private var opaqueBase: Color {
        colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90)
    }
}
