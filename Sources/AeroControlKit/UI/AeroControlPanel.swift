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
        return VStack(spacing: AeroControlLayout.pillGap) {
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

    private var usable: CGSize { AeroControlLayout.usable(available) }

    /// The result takes over the grid's geometry: a query that found something draws only the
    /// workspaces that hold a match, each with only its matching windows, in the same lattice
    /// as the full map. A query that found nothing leaves the whole map standing, so there is
    /// always something to read your way out of.
    private func grid(_ matches: [ParsedWindow]) -> some View {
        let filtered = state.model.workspaces(holding: matches)
        let filtering = !filtered.isEmpty
        let all = filtering ? filtered : state.model.workspaces
        let cards = AeroControlLayout.mapLayout(workspaces: all, sizes: state.previewSizes, screens: screenFrames, available: available, usable: usable, filtering: filtering)
        return ZStack(alignment: .topLeading) {
            ForEach(zip(all, cards).map { $0 }, id: \.0.name) { workspace, card in
                AeroControlWorkspaceCard(workspace: workspace, card: card, filtering: filtering)
                    .offset(x: card.frame.minX, y: card.frame.minY)
                    .transition(unsafe .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: usable.width, height: usable.height, alignment: .topLeading)
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
        // The cards as drawn, for the keys and the pointer (`OverviewStore.drawn`).
        .onChange(of: cards, initial: true) { _, cards in state.drawn = cards.map(\.grid) }
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
