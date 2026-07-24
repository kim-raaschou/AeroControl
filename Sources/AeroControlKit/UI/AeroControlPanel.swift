import SwiftUI
import Common

public struct AeroControlPanel: View {
    @Bindable var state: OverviewStore
    let settings: SettingsStore
    let displayKey: String?
    let displayIsBuiltin: Bool
    let screenFilter: Int?
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

    private var resolvedOrientation: Orientation {
        if let displayKey {
            return settings.config(forKey: displayKey, isBuiltin: displayIsBuiltin).edge.orientation
        }
        return settings.orientation
    }

    private var resolvedIconSize: CGFloat {
        if let displayKey {
            return settings.config(forKey: displayKey, isBuiltin: displayIsBuiltin).iconSize
        }
        return settings.effectiveIconSize
    }

    private var workspaces: [WorkspaceInfo] {
        if let screenFilter {
            return state.model.workspaces(forScreen: screenFilter)
        }
        return state.model.workspaces
    }

    private var visibleMonitors: [MonitorInfo] {
        if screenFilter != nil {
            return Array(Set(workspaces.map(\.monitorId))).sorted().map(MonitorInfo.init)
        }
        return state.model.monitors
    }

    public static let floatingMargin: CGFloat = 2

    public var body: some View {
        Group {
            if let errorMsg = state.error {
                errorView(errorMsg)
            } else if workspaces.isEmpty {
                Color.clear.frame(width: 0, height: 0)
            } else {
                cardRow(iconSize: renderedIconSize)
            }
        }
        .padding(Self.floatingMargin)
        .fixedSize()
    }

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
        .padding(
            vertical ? .vertical : .horizontal,
            metrics.cardSpacing - Self.floatingMargin + AeroControlWorkspaceCard.focusPlateEdgeInset
        )
    }

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
