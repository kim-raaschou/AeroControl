import SwiftUI
import Common

/// The full-screen overview content: every workspace as a card, in rows sized by how much
/// each one holds.
public struct AeroControlPanel: View {
    @Bindable var state: OverviewStore
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    /// Called after an action that completes the "one shot" (focus a window or a
    /// workspace); the host hides the overview.
    let onDismiss: () -> Void

    public init(
        state: OverviewStore,
        availableWidth: CGFloat = 0,
        availableHeight: CGFloat = 0,
        onDismiss: @escaping () -> Void = {}
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
                Color.clear.frame(width: 0, height: 0)
            } else {
                grid
            }
        }
        .fixedSize()
    }

    private var usable: CGSize {
        CGSize(width: availableWidth * AeroControlLayout.usableScreenFraction,
               height: availableHeight * AeroControlLayout.usableScreenFraction)
    }

    /// A screen map when the store has a frame for exactly this workspace's windows and none
    /// of them overlap; decided here, once, for both the layout and the card.
    private func map(_ workspace: WorkspaceInfo, previews: Bool) -> WorkspaceMap? {
        let ids = workspace.windows.map(\.windowId)
        guard previews, let cached = state.frames[workspace.name], Set(cached.keys) == Set(ids) else { return nil }
        let frames = ids.map { cached[$0]! }
        let floating = workspace.windows.map(\.isFloating)
        return AeroControlLayout.mapBounds(frames: frames, floating: floating)
            .map { WorkspaceMap(frames: frames, bounds: $0) }
    }

    /// Cell aspect of a grid card: the median of its snapshots', the screen's when none.
    private func gridAspect(_ workspace: WorkspaceInfo) -> CGFloat {
        let sizes = workspace.windows.compactMap { state.previews[$0.windowId]?.size }
        return AeroControlLayout.cellAspect(snapshotSizes: sizes, fallback: AeroControlLayout.previewAspect(for: usable))
    }

    private var grid: some View {
        let all = workspaces
        let previews = state.previewsAvailable
        let namesMonitors = self.namesMonitors
        let maps = all.map { map($0, previews: previews) }
        let sizes = AeroControlLayout.cardSizes(
            windowCounts: all.map { $0.windows.count },
            aspects: zip(all, maps).map { $1.map { $0.bounds.height / $0.bounds.width } ?? gridAspect($0) },
            cells: zip(all, maps).map { $1 == nil ? $0.windows.count : 1 },
            emptyWidth: namesMonitors ? AeroControlLayout.namedEmptyCardWidth : AeroControlLayout.emptyCardWidth,
            available: usable
        )
        var index = 0
        let rows: [[(WorkspaceInfo, CGSize, WorkspaceMap?)]] = sizes.map { row in
            row.map { size in defer { index += 1 }; return (all[index], size, maps[index]) }
        }
        return VStack(spacing: AeroControlLayout.cardGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: AeroControlLayout.cardGap) {
                    ForEach(row, id: \.0.id) { workspace, size, map in
                        card(for: workspace, size: size, map: map, previews: previews,
                             monitor: namesMonitors ? workspace.monitorShortName : nil)
                    }
                }
            }
        }
    }

    private func card(for workspace: WorkspaceInfo, size: CGSize, map: WorkspaceMap?,
                      previews: Bool, monitor: String?) -> some View {
        AeroControlWorkspaceCard(
            workspace: workspace,
            monitorName: monitor,
            isFocused: workspace.name == state.model.focusedWorkspace,
            focusedWindowId: state.model.focusedWindowId,
            icons: state.icons,
            previews: state.previews,
            map: map,
            showPreviews: previews,
            previewAspect: gridAspect(workspace),
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
