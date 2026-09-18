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
        // Once per pass: matching is a scan of every window's name and title, on every keystroke.
        let matches = state.filterMatches
        // The pill sits under the result rather than over it: the cards are only as tall as
        // their pictures need now, so an overlay at the bottom would land on a card edge.
        return VStack(spacing: Self.pillGap) {
            if let errorMsg = state.error {
                errorView(errorMsg)
            } else if workspaces.isEmpty {
                EmptyView()
            } else {
                grid(matches)
            }
            AeroControlFilterPill(query: state.filter, matchCount: matches.count)
        }
        .fixedSize()
        .environment(state)
        .environment(\.aeroDismiss, onDismiss)
    }

    /// The grid's box. The query's lane comes out of it rather than being added to it: added,
    /// the panel grew taller than the screen the moment anything was typed, and the lane was
    /// clipped off the bottom.
    private var usable: CGSize {
        CGSize(width: availableWidth * AeroControlLayout.usableScreenFraction,
               height: availableHeight * AeroControlLayout.usableScreenFraction
                   - AeroControlFilterPill.laneHeight - Self.pillGap)
    }

    private static let pillGap: CGFloat = 18

    /// Cell aspect of a grid card: the median of its snapshots', the screen's when none.
    private func gridAspect(_ workspace: WorkspaceInfo) -> CGFloat {
        let sizes = workspace.windows.compactMap { state.previews[$0.windowId]?.size }
        return AeroControlLayout.cellAspect(snapshotSizes: sizes, fallback: AeroControlLayout.previewAspect(for: usable))
    }

    /// The result takes over the grid's geometry: a query that found something draws only the
    /// workspaces that hold a match, each with only its matching windows, sized by the same
    /// `cardRows` as the full grid — it counts windows and knows nothing of workspaces. A
    /// query that found nothing leaves the whole map standing, so there is always something
    /// to read your way out of.
    private func grid(_ matches: [ParsedWindow]) -> some View {
        let filtered = state.model.workspaces(holding: matches)
        let filtering = !filtered.isEmpty
        let all = filtering ? filtered : workspaces
        let namesMonitors = self.namesMonitors
        var rows = AeroControlLayout.cardRows(
            windowCounts: all.map { $0.windows.count },
            emptyWidth: namesMonitors ? AeroControlLayout.namedEmptyCardWidth : AeroControlLayout.emptyCardWidth,
            available: usable
        )
        // A result may be shorter than the screen; a map may not.
        if filtering { rows = rows.map { shrunk($0, of: all) } }
        return VStack(spacing: AeroControlLayout.cardGap) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: AeroControlLayout.cardGap) {
                    ForEach(row) { cell in
                        let workspace = all[cell.index]
                        AeroControlWorkspaceCard(
                            workspace: workspace,
                            monitorName: namesMonitors ? workspace.monitorShortName : nil,
                            previewAspect: gridAspect(workspace),
                            size: cell.size,
                            filtering: filtering
                        )
                        .transition(unsafe .opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
            }
        }
        // The unfiltered grid is a map and never moves; the filtered one is a result, and
        // re-flows as the query narrows. Animated, or every letter would snap.
        .animation(.easeInOut(duration: 0.15), value: all)
    }

    /// Gives a row back the height its tiles cannot use, so two matches are two big pictures
    /// rather than two small ones adrift in a full-height card.
    private func shrunk(_ row: [AeroControlLayout.Cell], of all: [WorkspaceInfo]) -> [AeroControlLayout.Cell] {
        guard let height = row.first?.size.height else { return row }
        let used = AeroControlLayout.usedHeight(
            windowCounts: row.map { all[$0.index].windows.count },
            widths: row.map(\.size.width),
            aspects: row.map { gridAspect(all[$0.index]) },
            available: height
        )
        return row.map { AeroControlLayout.Cell(index: $0.index, size: CGSize(width: $0.size.width, height: used)) }
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.system(.callout)).foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }
}
