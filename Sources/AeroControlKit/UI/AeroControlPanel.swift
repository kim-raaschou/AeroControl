import SwiftUI
import Common

/// The full-screen overview content: every workspace as a card, in even rows of equal-sized
/// cards.
public struct AeroControlPanel: View {
    @Bindable var state: OverviewStore
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    /// Called after an action that completes the "one shot" (focus a window or a
    /// workspace); the host hides the overview.
    let onDismiss: @MainActor () -> Void

    public init(
        state: OverviewStore,
        availableWidth: CGFloat = 0,
        availableHeight: CGFloat = 0,
        onDismiss: @escaping @MainActor () -> Void = {}
    ) {
        self._state = Bindable(wrappedValue: state)
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
        self.onDismiss = onDismiss
    }

    /// Every workspace, whichever monitor it lives on: the overview is one window.
    private var workspaces: [WorkspaceInfo] { state.model.workspaces }

    /// With one display the cards say nothing about it; with several, each card names its own.
    private var namesMonitors: Bool { state.model.spansMonitors }

    public var body: some View {
        Group {
            if let errorMsg = state.error {
                errorView(errorMsg)
            } else if workspaces.isEmpty {
                EmptyView()
            } else {
                grid
            }
        }
        .fixedSize()
        .environment(state)
        .environment(\.aeroDismiss, onDismiss)
    }

    private var usable: CGSize {
        CGSize(width: availableWidth * AeroControlLayout.usableScreenFraction,
               height: availableHeight * AeroControlLayout.usableScreenFraction)
    }

    /// Cell aspect of a grid card: the median of its snapshots', the screen's when none.
    private func gridAspect(_ workspace: WorkspaceInfo) -> CGFloat {
        let sizes = workspace.windows.compactMap { state.previews[$0.windowId]?.size }
        return AeroControlLayout.cellAspect(snapshotSizes: sizes, fallback: AeroControlLayout.previewAspect(for: usable))
    }

    private var grid: some View {
        let all = workspaces
        let namesMonitors = self.namesMonitors
        let rows = AeroControlLayout.cardRows(
            windowCounts: all.map { $0.windows.count },
            emptyWidth: namesMonitors ? AeroControlLayout.namedEmptyCardWidth : AeroControlLayout.emptyCardWidth,
            available: usable
        )
        return VStack(spacing: AeroControlLayout.cardGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: AeroControlLayout.cardGap) {
                    ForEach(row) { cell in
                        let workspace = all[cell.index]
                        AeroControlWorkspaceCard(
                            workspace: workspace,
                            monitorName: namesMonitors ? workspace.monitorShortName : nil,
                            previewAspect: gridAspect(workspace),
                            size: cell.size
                        )
                        .transition(unsafe .opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
        }
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.system(.callout)).foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }
}
