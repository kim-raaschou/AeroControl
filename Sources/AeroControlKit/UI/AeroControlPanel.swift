import SwiftUI
import Common

/// The full-screen overview content: every workspace as a card, in even rows of equal-sized
/// cards.
public struct AeroControlPanel: View {
    let state: OverviewStore
    @Environment(\.aeroLook) private var look
    /// The screen the overview covers.
    let available: CGSize
    /// The visible frame of every screen in AeroSpace's coordinates (points, top-left origin),
    /// by AeroSpace's 1-based AppKit index: the area a workspace's layout fills, and the shape a
    /// window nothing is known about gets.
    let screenFrames: [Int: CGRect]

    public init(state: OverviewStore, available: CGSize = .zero, screenFrames: [Int: CGRect] = [:]) {
        self.state = state
        self.available = available
        self.screenFrames = screenFrames
    }

    public var body: some View {
        let matches = state.filterMatches
        // The pill sits under the result rather than over it: the cards are only as tall as
        // their pictures need now, so an overlay at the bottom would land on a card edge.
        // A missing app has the lane alone; a map without workspaces has nothing to draw.
        return VStack(spacing: Self.pillGap) {
            if let errorMsg = state.error {
                errorView(errorMsg)
            } else if state.model.workspaces.isEmpty || state.missingApp != nil {
                EmptyView()
            } else if state.strip != nil, !state.stripWindows.isEmpty {
                AeroControlAppStrip(usable: usable, screens: screenFrames, fallbackScreen: CGRect(origin: .zero, size: available))
            } else {
                grid(matches)
            }
            AeroControlFilterPill(matchCount: matches.count)
        }
        .fixedSize()
        .environment(state)
    }

    /// The grid's box. The query's lane comes out of it rather than being added to it: added,
    /// the panel grew taller than the screen the moment anything was typed, and the lane was
    /// clipped off the bottom.
    private var usable: CGSize {
        CGSize(width: available.width * AeroControlLayout.usableScreenFraction,
               height: available.height * AeroControlLayout.usableScreenFraction
                   - AeroControlFilterPill.laneHeight - Self.pillGap)
    }

    private static let pillGap: CGFloat = 18

    /// The result takes over the grid's geometry: a query that found something draws only the
    /// workspaces that hold a match, each with only its matching windows, in the same lattice
    /// as the full map. A query that found nothing leaves the whole map standing, so there is
    /// always something to read your way out of.
    private func grid(_ matches: [ParsedWindow]) -> some View {
        let filtered = state.model.workspaces(holding: matches)
        let filtering = !filtered.isEmpty
        let all = filtering ? filtered : state.model.workspaces
        // The shape of a card: this screen's, as GNOME and KWin shape their workspace cells.
        let frames = CardGrid.lattice(count: all.count, in: usable, cellRatio: AeroControlLayout.screenRatio(for: available), gap: AeroControlLayout.cardGap,
                                      chrome: CGSize(width: 2 * AeroControlLayout.cardPadding, height: AeroControlLayout.cardChrome))
        return ZStack(alignment: .topLeading) {
            ForEach(frames.indices, id: \.self) { i in
                let workspace = all[i]
                AeroControlWorkspaceCard(
                    workspace: workspace,
                    screen: screenFrames[workspace.screenIndex],
                    size: frames[i].size,
                    filtering: filtering
                )
                .offset(x: frames[i].minX, y: frames[i].minY)
                .transition(unsafe .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: usable.width, height: usable.height, alignment: .topLeading)
        // The map holds still through ordinary churn; the filtered result re-flows as the
        // query narrows. Animated, or every letter would snap.
        .animation(.easeInOut(duration: 0.15 * look.motion), value: all)
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.system(.callout)).foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }
}
