import SwiftUI
import Common

/// The picker for "which of this app's windows", as krn.overview lays it out and as the map
/// draws it: one row of the map's own cards, one per workspace holding the app, each in its
/// screen's shape at one height — the app's windows where AeroSpace put them, the other
/// apps' grey, half there, framed and out of reach. The app's name and the marked window's title
/// stand in the map's pill under the row. A row that fits stands still; one that does not slides
/// to keep the marked card in the middle, up to its ends, the cards the edges cut dimmed.
/// The marking only chooses: Enter, a window's key (⌘1–⌘f, on its corner) or a click
/// focuses; the summon key again steps, as Cmd-` does; Escape goes back.
struct AeroControlAppStrip: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look

    let usable: CGSize
    let screens: [Int: CGRect]
    let fallbackScreen: CGRect

    /// How long the row takes to slide a card along.
    private static let turn: Double = 0.4
    /// How much shows of a card the view's edge cuts: the whole card dimmed, its border with it,
    /// so the row reads as going on to that side and the workspace in the middle stands out.
    private static let cutCard: Double = 0.5

    var body: some View {
        let groups = state.stripWorkspaces
        let bundleId = state.strip?.app ?? ""
        let layout = AeroControlLayout.stripLayout(groups: groups, bundleId: bundleId, sizes: state.previewSizes, screens: screens,
                                                   fallbackScreen: fallbackScreen, viewWidth: usable.width, panelHeight: usable.height)
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
        // The row slides a card along when the keys take the marking to another workspace;
        // stepping within a card, or pointing, leaves it.
        .animation(.smooth(duration: Self.turn * look.motion), value: held ?? -1)
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
        .onChange(of: layout.cards, initial: true) { _, cards in
            state.drawn = cards.map { c in (frame: CGRect(x: c.span.x, y: 0, width: c.span.width, height: layout.height),
                                                 windows: c.frames.filter { !c.others.contains($0.key) }.mapValues { $0.offsetBy(dx: c.span.x + AeroControlLayout.cardPadding, dy: 0) }) }   // the app's own: the others are not stops
        }
    }

    /// Every window of the workspace at its place, the other apps' faint and taking no input:
    /// the rest of the workspace, so the card reads as the whole of it, framed with its app's
    /// icon, and out of reach. The app's own carry their key, and pointing at one marks it.
    private func windowsOf(_ workspace: WorkspaceInfo, _ laid: AeroControlLayout.StripCard, ids: [Int]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(workspace.windows.filter { laid.frames[$0.windowId] != nil }, id: \.windowId) { window in
                let frame = laid.frames[window.windowId]!
                let mine = !laid.others.contains(window.windowId)
                let label = ids.firstIndex(of: window.windowId).flatMap(AppStripModel.keyLabel)
                AeroControlAppTile(window: window, size: frame.size, filtering: false,
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
