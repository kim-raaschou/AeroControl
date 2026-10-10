import SwiftUI
import Common

public struct AeroControlPanel: View {
    let state: OverviewStore
    @Environment(\.aeroLook) private var look
    @Namespace private var tiles

    public init(state: OverviewStore) { self.state = state }

    public var body: some View {
        return ZStack {
            content
            if state.showingHelp { AeroControlKeyHelp() }
        }
        .fixedSize()
        .environment(state)
    }

    private var content: some View {
        VStack(spacing: AeroControlLayout.pillGap) {
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
    }

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
