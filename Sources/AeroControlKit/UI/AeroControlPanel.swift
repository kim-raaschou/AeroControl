import SwiftUI
import Common

/// Free-floating, content-sized AeroControl overview. A single movable row (or
/// column) of workspace cards that floats above the desktop, showing **every**
/// workspace grouped by the monitor it lives on (a thin separator divides the
/// groups, ordered by monitor id ≈ physical left-to-right). The hosting window
/// resizes itself to this view's fitting size and follows the focused monitor.
/// Every workspace card has the same cross-axis size; its main-axis length scales
/// with how many apps it holds, so busy workspaces are larger than quiet ones.
public struct AeroControlPanel: View {
    @Bindable var state: OverviewStore
    /// Observed runtime settings — reading `iconSize` / `orientation` here makes the
    /// panel reflow the instant the user changes them from the menu.
    let settings: SettingsStore
    /// The focused screen's available extent (visibleFrame size), so the widget can
    /// shrink its icons to fit rather than overflowing a busy workspace off-screen. Zero
    /// means "unconstrained" (e.g. previews/tests) — the preferred size is used as-is.
    let availableWidth: CGFloat
    let availableHeight: CGFloat

    public init(
        state: OverviewStore,
        settings: SettingsStore,
        availableWidth: CGFloat = 0,
        availableHeight: CGFloat = 0
    ) {
        self._state = Bindable(wrappedValue: state)
        self.settings = settings
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
    }

    private var workspaces: [WorkspaceInfo] {
        state.model.workspaces
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
                loadingView
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
        let extent = settings.orientation.isVertical ? availableHeight : availableWidth
        guard extent > 0 else { return settings.effectiveIconSize }
        let counts = workspaces.map { $0.windows.count }
        return AeroControlLayout.effectiveIconSize(
            preferred: settings.effectiveIconSize,
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
        let vertical = settings.orientation.isVertical
        let layout = vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.cardSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: metrics.cardSpacing))
        return layout {
            ForEach(Array(state.model.monitors.enumerated()), id: \.element.id) { index, monitor in
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
            isVertical: settings.orientation.isVertical
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

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small).tint(.white)
            Text("Loading workspaces…")
                .font(.system(.callout, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}
