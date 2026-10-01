import SwiftUI
import Common

/// The full-screen overview content: every workspace as a card, in even rows of equal-sized
/// cards.
public struct AeroControlPanel: View {
    @Bindable var state: OverviewStore
    @Environment(\.aeroMotion) private var motion
    let availableWidth: CGFloat
    let availableHeight: CGFloat
    /// Width / height of every screen, by AeroSpace's 1-based AppKit index: a card takes the
    /// shape of the screen its workspace is on.
    let screenRatios: [Int: CGFloat]
    /// Called after an action that completes the "one shot" (focus a window or a
    /// workspace); the host hides the overview.
    let onDismiss: @MainActor () -> Void

    public init(
        state: OverviewStore,
        availableWidth: CGFloat = 0,
        availableHeight: CGFloat = 0,
        screenRatios: [Int: CGFloat] = [:],
        onDismiss: @escaping @MainActor () -> Void = {}
    ) {
        self._state = Bindable(wrappedValue: state)
        self.availableWidth = availableWidth
        self.availableHeight = availableHeight
        self.screenRatios = screenRatios
        self.onDismiss = onDismiss
    }

    /// Every workspace, whichever monitor it lives on: the overview is one window.
    private var workspaces: [WorkspaceInfo] { state.model.workspaces }

    /// With one display the cards say nothing about it; with several, each card names its own.
    private var namesMonitors: Bool { state.model.spansMonitors }

    public var body: some View {
        let matches = state.filterMatches
        // The pill sits under the result rather than over it: the cards are only as tall as
        // their pictures need now, so an overlay at the bottom would land on a card edge.
        return VStack(spacing: Self.pillGap) {
            if let errorMsg = state.error {
                errorView(errorMsg)
            } else if workspaces.isEmpty {
                EmptyView()
            } else if state.presentation == .strip, !matches.isEmpty {
                AeroControlAppStrip(matches: matches, usable: usable, fallbackRatio: AeroControlLayout.screenRatio(for: usable))
            } else {
                grid(matches)
            }
            // In the strip the header already names the app; the pill only speaks when the
            // query has gone past that.
            AeroControlFilterPill(query: state.presentation == .strip && state.filter == matches.first?.window.appName ? "" : state.filter,
                                  matchCount: matches.count)
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

    /// The shape of a card: this screen's, as GNOME and KWin shape their workspace cells.
    private var cellRatio: CGFloat { AeroControlLayout.screenRatio(for: CGSize(width: availableWidth, height: availableHeight)) }

    /// The shape of the screen a workspace lives on; this screen's when AeroSpace did not say.
    private func ratio(of workspace: WorkspaceInfo) -> CGFloat {
        screenRatios[workspace.screenIndex] ?? AeroControlLayout.screenRatio(for: usable)
    }

    /// The result takes over the grid's geometry: a query that found something draws only the
    /// workspaces that hold a match, each with only its matching windows, in the same lattice
    /// as the full map. A query that found nothing leaves the whole map standing, so there is
    /// always something to read your way out of.
    private func grid(_ matches: [ParsedWindow]) -> some View {
        let filtered = state.model.workspaces(holding: matches)
        let filtering = !filtered.isEmpty
        let all = filtering ? filtered : workspaces
        let namesMonitors = self.namesMonitors
        let layout = CardGrid.lattice(count: all.count, in: usable, cellRatio: cellRatio, gap: AeroControlLayout.cardGap,
                                      chrome: CGSize(width: 2 * AeroControlLayout.cardPadding, height: AeroControlLayout.cardChrome))
        let cardRows = layout.rows.map { $0.map { all[$0].name } }
        return ZStack(alignment: .topLeading) {
            ForEach(layout.cells, id: \.index) { cell in
                let workspace = all[cell.index]
                AeroControlWorkspaceCard(
                    workspace: workspace,
                    monitorName: namesMonitors ? workspace.monitorShortName : nil,
                    fallbackRatio: ratio(of: workspace),
                    size: cell.frame.size,
                    filtering: filtering
                )
                .offset(x: cell.frame.minX, y: cell.frame.minY)
                .transition(unsafe .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: usable.width, height: usable.height, alignment: .topLeading)
        // The map holds still through ordinary churn; the filtered result re-flows as the
        // query narrows. Animated, or every letter would snap.
        .animation(.easeInOut(duration: 0.15 * motion), value: all)
        .onChange(of: cardRows, initial: true) { _, cardRows in state.cardRows = cardRows }   // for ↑/↓ across cards
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.system(.callout)).foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }
}
