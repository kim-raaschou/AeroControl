import SwiftUI
import Common

/// The full-screen overview content: every workspace as a card, in even rows of equal-sized cards,
/// as the store lays them out (`OverviewStore.cards`) on the screen the host gave it.
public struct AeroControlPanel: View {
    let state: OverviewStore
    @Environment(\.aeroLook) private var look
    /// One namespace for every tile, so a window that moves to another card is the same view to
    /// SwiftUI and glides there (`matchedGeometryEffect`) rather than going out and coming in.
    @Namespace private var tiles

    public init(state: OverviewStore) { self.state = state }

    public var body: some View {
        // The pill sits under the result, in a lane the grid reserves; a missing app has the lane alone.
        return VStack(spacing: AeroControlLayout.pillGap) {
            if let errorMsg = state.error {
                errorView(errorMsg)
            } else if state.model.workspaces.isEmpty || state.missingApp != nil {
                EmptyView()
            } else if state.strip != nil, !state.stripWindows.isEmpty {
                AeroControlAppStrip(tiles: tiles)
                    .environment(\.aeroLook, AeroLook(palette: look.palette, motion: look.motion, surface: .strip))
            } else {
                grid
            }
            AeroControlFilterPill(matchCount: state.filterMatches.count)
        }
        .fixedSize()
        .environment(state)
    }

    /// The map as the store lays it out: a query that found something draws only the workspaces
    /// that hold a match, each with only its matching windows, in the same lattice as the full map.
    private var grid: some View {
        let shown = state.shown, filtering = state.filtering, usable = state.usable
        return ZStack(alignment: .topLeading) {
            ForEach(zip(shown, state.cards).map { $0 }, id: \.0.name) { workspace, card in
                AeroControlWorkspaceCard(workspace: workspace, card: card, filtering: filtering, tiles: tiles)
                    .offset(x: card.frame.minX, y: card.frame.minY)
                    .transition(unsafe .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: usable.width, height: usable.height, alignment: .topLeading)
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
        // The filtered result re-flows as the query narrows; animated, or every letter would snap.
        .animation(.easeInOut(duration: 0.15 * look.motion), value: shown)
    }

    private func errorView(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
            Text(message).font(.system(.callout)).foregroundStyle(.white.opacity(0.8))
        }
        .padding()
    }
}
