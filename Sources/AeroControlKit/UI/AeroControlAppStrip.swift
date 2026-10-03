import SwiftUI
import Common

/// The picker for "which of this app's windows", as krn.overview lays it out and as the map
/// draws it: one row of the map's own cards, one per workspace holding the app, each in its
/// screen's shape at one height — the app's windows where AeroSpace put them, the other
/// apps' grey, half there, framed and out of reach. The app's name and the marked window's title
/// stand in the map's pill under the row. From three cards, or when they do not fit, the row is a
/// ring with the marked card in the middle, whole to both edges, turning a card at a time.
/// The marking only chooses: Enter, a window's key (⌘1–⌘9, on its corner) or a click
/// focuses; the summon key again steps, as Cmd-` does; Escape goes back.
struct AeroControlAppStrip: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroMotion) private var motion

    let usable: CGSize
    let screens: [Int: CGRect]
    let fallbackScreen: CGRect
    let namesMonitors: Bool

    /// How long the ring takes to turn a card along.
    private static let turn: Double = 0.4
    /// How far in from each edge of the view a card cut by it fades out, rather than ending in mid-air.
    private static let edgeFade: CGFloat = 0.03

    var body: some View {
        let windows = state.stripWindows
        let groups = state.stripWorkspaces
        let bundleId = state.strip?.bundleId ?? ""
        let layout = AeroControlLayout.stripLayout(groups: groups, bundleId: bundleId, sizes: state.previewSizes, screens: screens,
                                                   fallbackScreen: fallbackScreen, viewWidth: usable.width, panelHeight: usable.height)
        let ids = windows.map(\.window.windowId)
        let centre = state.strip?.centre ?? state.strip?.marked
        let turns = state.strip?.turns ?? 0
        let placements = AeroControlLayout.stripPlacements(layout, centre: centre, turns: turns, viewWidth: usable.width)
        let held = layout.cards.firstIndex { card in centre.map { card.frames[$0] != nil } ?? false }
        return ZStack(alignment: .topLeading) {
            ForEach(placements, id: \.self.identity) { placed in
                let workspace = groups[placed.card], laid = layout.cards[placed.card]
                AeroControlCardFace(workspace: workspace, monitorName: namesMonitors ? workspace.monitorShortName : nil,
                                    size: CGSize(width: laid.span.width, height: layout.height)) {
                    windowsOf(workspace, laid, ids: ids)
                }
                .opacity(placed.shown ? 1 : 0)
                .allowsHitTesting(placed.shown)
                .offset(x: placed.x)
            }
        }
        .frame(width: usable.width, height: layout.height, alignment: .topLeading)
        .mask(edges(fading: layout.runsRound(in: usable.width)))
        // The ring turns a card along when the keys take the marking to another workspace, the
        // same way round past the last; stepping within a card, or pointing, leaves it.
        .animation(.smooth(duration: Self.turn * motion), value: [held ?? -1, turns])
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
    }

    /// A ring cuts cards at the view's edges, and they fade there rather than end in mid-air; a row
    /// standing still is whole and keeps its edges.
    private func edges(fading: Bool) -> LinearGradient {
        let fade = fading ? Self.edgeFade : 0
        return LinearGradient(stops: [.init(color: fading ? .clear : .black, location: 0), .init(color: .black, location: fade),
                                      .init(color: .black, location: 1 - fade), .init(color: fading ? .clear : .black, location: 1)],
                              startPoint: .leading, endPoint: .trailing)
    }

    /// Every window of the workspace at its place, the other apps' faint and taking no input.
    private func windowsOf(_ workspace: WorkspaceInfo, _ laid: AeroControlLayout.StripCard, ids: [Int]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(workspace.windows.filter { laid.frames[$0.windowId] != nil }, id: \.windowId) { window in
                let frame = laid.frames[window.windowId]!
                if laid.others.contains(window.windowId) {
                    // The rest of the workspace, so the card reads as the whole of it: faded and framed,
                    // with its app's icon, and out of reach.
                    tile(window, frame, mine: false).allowsHitTesting(false)
                        .offset(x: frame.minX, y: frame.minY)
                } else {
                    // The hover belongs to the window's own frame, so it goes on before the window is moved there.
                    let label = ids.firstIndex(of: window.windowId).flatMap(AppStripModel.keyLabel)
                    tile(window, frame, mine: true, key: label.map { ($0, window.windowId == state.strip?.marked) })
                        .onHover { if $0 { state.pointStrip(window.windowId, at: NSEvent.mouseLocation) } }
                        .offset(x: frame.minX, y: frame.minY)
                        .zIndex(1)
                }
            }
        }
    }

    /// Every window where the map draws it, untitled as on the map: the app's own with their key
    /// where the map has the icon, the others with their icon.
    private func tile(_ window: WindowInfo, _ frame: CGRect, mine: Bool, key: (label: String, marked: Bool)? = nil) -> some View {
        AeroControlAppTile(window: window, metrics: AeroControlMetrics(tileSize: frame.size), filtering: false, showsIcon: !mine, key: key,
                           faded: !mine)
            .frame(width: frame.width, height: frame.height)
    }
}
