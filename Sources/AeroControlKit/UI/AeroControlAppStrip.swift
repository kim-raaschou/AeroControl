import SwiftUI
import Common

struct AeroControlAppStrip: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    let tiles: Namespace.ID

    private static let turn: Double = 0.4
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
        .animation(.smooth(duration: Self.turn * look.motion), value: held ?? -1)
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
    }

    private func windowsOf(_ workspace: WorkspaceInfo, _ laid: AeroControlLayout.StripCard, ids: [Int]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(workspace.windows.filter { laid.frames[$0.windowId] != nil }, id: \.windowId) { window in
                let frame = laid.frames[window.windowId]!
                let mine = !laid.others.contains(window.windowId)
                let label = ids.firstIndex(of: window.windowId).flatMap(AppStripModel.keyLabel)
                AeroControlAppTile(window: window, size: frame.size, filtering: false, tiles: tiles,
                                   key: label.map { ($0, window.windowId == state.strip?.marked) }, faded: !mine)
                    .allowsHitTesting(mine)
                    .onHover { if mine, $0 { state.point(window.windowId, at: NSEvent.mouseLocation) } }
                    .offset(x: frame.minX, y: frame.minY)
                    .zIndex(mine ? 1 : 0)
            }
        }
    }
}
