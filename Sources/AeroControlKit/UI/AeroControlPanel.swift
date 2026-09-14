import SwiftUI
import Common

/// The full-screen overview content: all workspaces (optionally only one screen's) as a
/// centered near-square grid of equal cards; the last row is centered when it is short.
public struct AeroControlPanel: View {
    @Bindable var state: OverviewStore
    let screenFilter: Int?
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    /// Called after an action that completes the "one shot" (focus a window or a
    /// workspace); the host hides the overview.
    let onDismiss: () -> Void

    public init(
        state: OverviewStore,
        screenFilter: Int? = nil,
        availableWidth: CGFloat = 0,
        availableHeight: CGFloat = 0,
        onDismiss: @escaping () -> Void = {}
    ) {
        self._state = Bindable(wrappedValue: state)
        self.screenFilter = screenFilter
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
        self.onDismiss = onDismiss
    }

    private var workspaces: [WorkspaceInfo] {
        if let screenFilter {
            return state.model.workspaces(forScreen: screenFilter)
        }
        return state.model.workspaces
    }

    public var body: some View {
        Group {
            if let errorMsg = state.error {
                errorView(errorMsg)
            } else if workspaces.isEmpty {
                Color.clear.frame(width: 0, height: 0)
            } else {
                grid
            }
        }
        .fixedSize()
    }

    private var grid: some View {
        let all = workspaces
        let columns = AeroControlLayout.columns(forCount: all.count)
        let usable = CGSize(
            width: availableWidth * AeroControlLayout.usableScreenFraction,
            height: availableHeight * AeroControlLayout.usableScreenFraction
        )
        let cardSize = AeroControlLayout.cardSize(count: all.count, available: usable)
        let rows = stride(from: 0, to: all.count, by: columns).map { Array(all[$0..<min($0 + columns, all.count)]) }
        return VStack(spacing: AeroControlLayout.cardGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: AeroControlLayout.cardGap) {
                    ForEach(row) { workspace in
                        card(for: workspace, size: cardSize)
                    }
                }
            }
        }
    }

    private func card(for workspace: WorkspaceInfo, size: CGSize) -> some View {
        AeroControlWorkspaceCard(
            workspace: workspace,
            isFocused: workspace.name == state.model.focusedWorkspace,
            focusedWindowId: state.model.focusedWindowId,
            icons: state.icons,
            previews: state.previews,
            size: size,
            onFocusWorkspace: { send(.focusWorkspace(workspace.name)); onDismiss() },
            onFocusWindow: { windowId in send(.focusWindow(windowId)); onDismiss() },
            onMoveWindow: { windowId, target in
                send(.moveWindow(windowId: windowId, toWorkspace: target))
            },
            onMergeWorkspace: { source, target in
                send(.mergeWorkspace(source: source, into: target))
            },
            onCloseWindow: { windowId in send(.closeWindow(windowId)) }
        )
        .transition(unsafe .opacity.combined(with: .scale(scale: 0.96)))
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
