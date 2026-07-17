import SwiftUI
import Common

/// Free-floating, content-sized AeroControl overview. A single movable row (or
/// column) of workspace cards that floats above the desktop, showing **every**
/// workspace grouped by the monitor it lives on (a thin separator divides the
/// groups, ordered by monitor id ≈ physical left-to-right). The hosting window
/// resizes itself to this view's fitting size and docks to the active display's edge.
/// Every workspace card has the same cross-axis size; its main-axis length scales
/// with how many apps it holds, so busy workspaces are larger than quiet ones.
public struct AeroControlPanel: View {
    @Bindable var state: OverviewStore
    /// Observed runtime settings — reading `iconSize` / `orientation` here makes the
    /// panel reflow the instant the user changes them from the menu.
    let settings: SettingsStore
    /// When set, the panel renders *this* display's config (edge/icon size) instead of
    /// the single "active" display — so several windows can each show their own screen's
    /// config in multi-screen mode. Nil falls back to the active-display accessors.
    let displayKey: String?
    let displayIsBuiltin: Bool
    /// When set (multi-screen mode), the panel shows *only* the workspaces physically on
    /// this window's screen, keyed by AeroSpace's 1-based `NSScreen.screens` index
    /// (`monitor-appkit-nsscreen-screens-id`), so each per-screen widget mirrors just its
    /// own display. Nil shows every monitor grouped (the single-widget default).
    let screenFilter: Int?
    /// The focused screen's available extent (visibleFrame size), so the widget can
    /// shrink its icons to fit rather than overflowing a busy workspace off-screen. Zero
    /// means "unconstrained" (e.g. previews/tests) — the preferred size is used as-is.
    let availableWidth: CGFloat
    let availableHeight: CGFloat

    public init(
        state: OverviewStore,
        settings: SettingsStore,
        displayKey: String? = nil,
        displayIsBuiltin: Bool = true,
        screenFilter: Int? = nil,
        availableWidth: CGFloat = 0,
        availableHeight: CGFloat = 0
    ) {
        self._state = Bindable(wrappedValue: state)
        self.settings = settings
        self.displayKey = displayKey
        self.displayIsBuiltin = displayIsBuiltin
        self.screenFilter = screenFilter
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
    }

    /// The dock orientation this panel renders at: its own display's when keyed,
    /// otherwise the active display's. Reading it in a SwiftUI body tracks the config.
    private var resolvedOrientation: Orientation {
        if let displayKey {
            return settings.config(forKey: displayKey, isBuiltin: displayIsBuiltin).edge.orientation
        }
        return settings.orientation
    }

    /// The icon size this panel renders at: its own display's when keyed, otherwise the
    /// active display's.
    private var resolvedIconSize: CGFloat {
        if let displayKey {
            return settings.config(forKey: displayKey, isBuiltin: displayIsBuiltin).iconSize
        }
        return settings.effectiveIconSize
    }

    /// The workspaces this panel renders: every one by default, or only those physically
    /// on this window's screen in multi-screen mode.
    private var workspaces: [WorkspaceInfo] {
        if let screenFilter {
            return state.model.workspaces(forScreen: screenFilter)
        }
        return state.model.workspaces
    }

    /// The monitor groups this panel lays out: every one by default, or just the single
    /// monitor physically on this screen in multi-screen mode (so no separators are
    /// drawn). Derived from the already-filtered workspaces, so it stays a 1:1 match.
    private var visibleMonitors: [MonitorInfo] {
        if screenFilter != nil {
            return Array(Set(workspaces.map(\.monitorId))).sorted().map(MonitorInfo.init)
        }
        return state.model.monitors
    }

    /// Empty margin around the card row so the cards don't touch the window edge and
    /// hover overlays that draw *outside* the tile (the per-app close button, the
    /// workspace badge) stay within the window and remain clickable.
    public static let floatingMargin: CGFloat = 2

    public var body: some View {
        Group {
            if let errorMsg = state.error {
                errorView(errorMsg)
            } else if workspaces.isEmpty {
                // Nothing to show yet (AeroSpace answers in <20ms) or — in multi-screen
                // mode — this display has no AeroSpace monitor. Render empty rather than a
                // spinner that would otherwise sit "Loading…" forever on such a screen.
                Color.clear.frame(width: 0, height: 0)
            } else {
                cardRow(iconSize: renderedIconSize)
            }
        }
        .padding(Self.floatingMargin)
        .fixedSize()
    }

    /// The icon size the panel actually renders at: the preferred (menu) size when the
    /// content fits the focused screen, otherwise the largest size at which the whole
    /// row (or column) fits within `usableScreenFraction` of that screen — so a busy
    /// workspace shrinks its icons instead of running off-screen. Falls back to the
    /// preferred size when the available extent is unknown (zero).
    private var renderedIconSize: CGFloat {
        let extent = resolvedOrientation.isVertical ? availableHeight : availableWidth
        guard extent > 0 else { return resolvedIconSize }
        let counts = workspaces.map { $0.windows.count }
        return AeroControlLayout.effectiveIconSize(
            preferred: resolvedIconSize,
            availableWidth: extent * AeroControlLayout.usableScreenFraction,
            windowCounts: counts
        )
    }

    /// Content-sized row (or column) of workspace cards, grouped by monitor, rendered at
    /// the given (possibly shrunk-to-fit) icon size. Horizontal orientation lays groups
    /// out left-to-right (fixed card *height*); vertical orientation stacks them
    /// top-to-bottom (fixed card *width*). A thin separator sits between adjacent monitor
    /// groups.
    private func cardRow(iconSize: CGFloat) -> some View {
        let metrics = AeroControlMetrics(iconSize: iconSize)
        let vertical = resolvedOrientation.isVertical
        let layout = vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.cardSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: metrics.cardSpacing))
        return layout {
            ForEach(Array(visibleMonitors.enumerated()), id: \.element.id) { index, monitor in
                if index > 0 {
                    groupSeparator(vertical: vertical, metrics: metrics)
                }
                ForEach(state.model.workspaces(forMonitor: monitor.monitorId)) { workspace in
                    card(for: workspace, iconSize: iconSize)
                        .fixedSize(horizontal: !vertical, vertical: vertical)
                        .frame(
                            width: vertical ? metrics.cardHeight : nil,
                            height: vertical ? nil : metrics.cardHeight
                        )
                }
            }
        }
        .fixedSize()
    }

    /// A Liquid Glass divider between two monitor groups, so the single widget shows
    /// which workspaces belong to which display without any text labels. It spans the
    /// cross axis (a card's fixed dimension) and is a slim `.regular` glass pill along
    /// the main axis, finished with a hairline rim so it reads as a deliberate glass
    /// element (matching the cards' crisp edge) rather than a flat line. Kept at 3pt so
    /// the fixed cross-axis extent and the row's fit-math stay unchanged.
    private func groupSeparator(vertical: Bool, metrics: AeroControlMetrics) -> some View {
        let thickness: CGFloat = 3
        return Color.clear
            .frame(
                width: vertical ? metrics.cardHeight : thickness,
                height: vertical ? thickness : metrics.cardHeight
            )
            .glassEffect(.regular, in: .capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
    }

    private func card(for workspace: WorkspaceInfo, iconSize: CGFloat) -> some View {
        AeroControlWorkspaceCard(
            workspace: workspace,
            isFocused: workspace.name == state.model.focusedWorkspace,
            focusedWindowId: state.model.focusedWindowId,
            icons: state.icons,
            iconSize: iconSize,
            onFocusWorkspace: { send(.focusWorkspace(workspace.name)) },
            onFocusWindow: { windowId in send(.focusWindow(windowId)) },
            onMoveWindow: { windowId, target in
                send(.moveWindow(windowId: windowId, toWorkspace: target))
            },
            onCloseWindow: { windowId in send(.closeWindow(windowId)) },
            isVertical: resolvedOrientation.isVertical
        )
        .transition(unsafe .opacity.combined(with: .scale(scale: 0.92)))
    }

    /// Fires an action at the state actor, weakly, so a dismissed panel can't keep
    /// the state alive.
    private func send(_ action: AeroControlAction) {
        Task { [weak state] in await state?.dispatch(action) }
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.system(.callout)).foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }
}
