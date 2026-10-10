import SwiftUI
import Common

/// The picker for which of this app's windows: one row of the map's cards, one per workspace
/// holding the app, the other apps' windows faint and out of reach.
struct AeroControlAppStrip: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    /// The panel's namespace for the tiles (`AeroControlPanel.tiles`).
    let tiles: Namespace.ID

    /// How long the row takes to slide a card along.
    private static let turn: Double = 0.4
    /// How much shows of a card the view's edge cuts: the whole card dimmed, its border with it, so
    /// the row reads as going on to that side and the workspace in the middle stands out.
    private static let cutCard: Double = 0.5

    var body: some View {
        let groups = state.stripWorkspaces, usable = state.usable, layout = state.stripLayout
        let ids = state.stripWindows.map(\.window.windowId)
        let centre = state.strip?.centre
        let placements = AeroControlLayout.stripPlacements(layout, centre: centre, viewWidth: usable.width)
        let held = layout.cards.firstIndex { card in centre.map { card.frames[$0] != nil } ?? false }
        return ZStack(alignment: .topLeading) {
            ForEach(placements, id: \.card) { placed in
                let workspace = groups[placed.card], laid = layout.cards[placed.card]
                AeroControlCardFace(workspace: workspace, size: CGSize(width: laid.span.width, height: layout.height)) {
                    windowsOf(workspace, laid, ids: ids)
                }
                .opacity(placed.x < 0 || placed.x + laid.span.width > usable.width ? Self.cutCard : 1)
                .offset(x: placed.x)
            }
        }
        .frame(width: usable.width, height: layout.height, alignment: .topLeading)
        .clipped()
        // The row slides when the keys take the marking to another workspace; pointing leaves it.
        .animation(.smooth(duration: Self.turn * look.motion), value: held ?? -1)
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
    }

    /// Every window of the workspace at its place, the other apps' faint and taking no input: the
    /// rest of the workspace, so the card reads as the whole of it, framed with its app's icon, and
    /// out of reach.
    private func windowsOf(_ workspace: WorkspaceInfo, _ laid: AeroControlLayout.StripCard, ids: [Int]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(workspace.windows.filter { laid.frames[$0.windowId] != nil }, id: \.windowId) { window in
                let frame = laid.frames[window.windowId]!
                let mine = !laid.others.contains(window.windowId)
                let label = ids.firstIndex(of: window.windowId).flatMap(AppStripModel.keyLabel)
                AeroControlAppTile(window: window, size: frame.size, filtering: false, tiles: tiles,
                                   key: label.map { ($0, window.windowId == state.strip?.marked) }, faded: !mine)
                    .allowsHitTesting(mine)
                    // The hover belongs to the window's own frame, so it goes on before the window is moved there.
                    .onHover { if mine, $0 { state.point(window.windowId, at: NSEvent.mouseLocation) } }
                    .offset(x: frame.minX, y: frame.minY)
                    .zIndex(mine ? 1 : 0)
            }
        }
    }
}
