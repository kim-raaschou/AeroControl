import SwiftUI
import Common

/// The picker for "which of this app's windows", as krn.overview lays it out and as the map
/// draws it: one row of the map's own cards, one per workspace holding the app, each in its
/// screen's shape at one height — the app's windows where AeroSpace put them, with their
/// titles as a filtered map has them, the other apps' grey, half there and out of reach. The
/// app's name stands in the map's pill under the row. When the cards do not fit, the row is a
/// ring with the marked card in the middle, moving a whole card at a time and never gliding.
/// The marking only chooses: Enter, a window's key (⌘1–⌘9, on its corner) or a click
/// focuses; the summon key again steps, as Cmd-` does; Escape goes back.
struct AeroControlAppStrip: View {
    @Environment(OverviewStore.self) private var state

    let usable: CGSize
    let screens: [Int: CGRect]
    let fallbackScreen: CGRect
    let gap: CGFloat?
    let namesMonitors: Bool

    /// The other apps' windows: there, so the workspace is whole, and plainly not what you are choosing.
    private static let othersOpacity: Double = 0.45
    /// How far in from each edge of the view a card cut by it fades out, rather than ending in mid-air.
    private static let edgeFade: CGFloat = 0.03

    var body: some View {
        let windows = state.stripWindows
        let groups = state.stripWorkspaces
        let bundleId = state.strip?.bundleId ?? ""
        let layout = AeroControlLayout.stripLayout(groups: groups, bundleId: bundleId, sizes: state.previewSizes, screens: screens,
                                                   fallbackScreen: fallbackScreen, gap: gap, viewWidth: usable.width, panelHeight: usable.height)
        let ids = windows.map(\.window.windowId)
        let shifts = AeroControlLayout.stripShifts(layout, centre: state.strip?.centre ?? state.strip?.marked, viewWidth: usable.width)
        return ZStack(alignment: .topLeading) {
            ForEach(Array(zip(groups, layout.cards).enumerated()), id: \.element.0.id) { g, pair in
                AeroControlCardFace(workspace: pair.0, monitorName: namesMonitors ? pair.0.monitorShortName : nil,
                                    orderUnknown: pair.1.orderUnknown, size: CGSize(width: pair.1.span.width, height: layout.height)) {
                    windowsOf(pair.0, pair.1, ids: ids)
                }
                .offset(x: pair.1.span.x + (shifts.indices.contains(g) ? shifts[g] : 0))
            }
        }
        .frame(width: usable.width, height: layout.height, alignment: .topLeading)
        .mask(edges(fading: layout.runsRound(in: usable.width)))
        .transaction { $0.animation = nil }          // nothing glides: AeroSpace switches without an animation
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
                    // The rest of the workspace, so the card reads as the whole of it: grey and half
                    // there, with its app's icon. krn.overview's 0.15 vanished on a dark card.
                    tile(window, frame, mine: false).saturation(0).opacity(Self.othersOpacity).allowsHitTesting(false)
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

    /// The app's own windows titled, as the filtered map titles its matches, and keyed where
    /// the map has the icon; the others with their icon and no title.
    private func tile(_ window: WindowInfo, _ frame: CGRect, mine: Bool, key: (label: String, marked: Bool)? = nil) -> some View {
        AeroControlAppTile(window: window, metrics: AeroControlMetrics(tileSize: frame.size), filtering: mine, showsIcon: !mine, key: key)
            .frame(width: frame.width, height: frame.height)
    }
}
