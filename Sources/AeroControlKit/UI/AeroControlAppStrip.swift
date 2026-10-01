import SwiftUI
import Common

/// The picker for "which of this app's windows", as krn.overview draws it: one row of cards,
/// one per workspace holding the app, each the map's own card of that workspace in its
/// screen's shape at one height — the app's windows where AeroSpace put them, the other
/// apps' grey, half there and out of reach. Over each card its workspace and a rule, in the accent on
/// the marked one. When the cards do not fit, the row is a ring with the marked card in the
/// middle, moving a whole card at a time and never gliding. The marking only chooses: Enter,
/// a window's key (1–9, a–f, on its corner) or a click focuses; the summon key again steps,
/// as Cmd-` does; Escape goes back.
struct AeroControlAppStrip: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme

    let usable: CGSize
    let screens: [Int: CGRect]
    let fallbackScreen: CGRect
    let gap: CGFloat?

    private static let margin: CGFloat = 48
    private static let padding: CGFloat = 24
    private static let cornerRadius: CGFloat = 22
    private static let cardRadius: CGFloat = 14
    private static let labelHeight: CGFloat = 22
    private static let labelGap: CGFloat = 8
    /// The other apps' windows: there, so the workspace is whole, and plainly not what you are choosing.
    private static let othersOpacity: Double = 0.45

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }
    private var viewWidth: CGFloat { usable.width - 2 * (Self.margin + Self.padding) }

    var body: some View {
        let windows = state.stripWindows
        let groups = state.stripWorkspaces
        let bundleId = state.strip?.bundleId ?? ""
        let layout = AeroControlLayout.stripLayout(groups: groups, bundleId: bundleId, sizes: state.previewSizes, screens: screens,
                                                   fallbackScreen: fallbackScreen, gap: gap, viewWidth: viewWidth, panelHeight: usable.height)
        let ids = windows.map(\.window.windowId)
        let marked = state.strip?.marked
        let markedCard = layout.cards.firstIndex { card in marked.map { card.frames[$0] != nil } ?? false }
        let shifts = AeroControlLayout.stripShifts(layout, centre: state.strip?.centre ?? marked, viewWidth: viewWidth)
        let band = Self.labelHeight + Self.labelGap
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return VStack(spacing: 18) {
            header(count: windows.count, workspaces: groups.count)
            ZStack(alignment: .topLeading) {
                ForEach(Array(zip(groups, layout.cards).enumerated()), id: \.element.0.id) { g, pair in
                    card(pair.0, pair.1, height: layout.height, ids: ids, centre: g == markedCard)
                        .offset(x: pair.1.span.x + (shifts.indices.contains(g) ? shifts[g] : 0))
                }
            }
            .frame(width: viewWidth, height: band + layout.height, alignment: .topLeading)
            .clipped()
            .transaction { $0.animation = nil }          // nothing glides: AeroSpace switches without an animation
        }
        .padding(Self.padding)
        .background { if let fill = palette.cardFill { shape.fill(fill) } else { shape.fill(.regularMaterial) } }
        .overlay(shape.strokeBorder(palette.cardBorder, lineWidth: 1))
        .clipShape(shape)
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
    }

    /// The app's name, and how many windows on how many workspaces.
    private func header(count: Int, workspaces: Int) -> some View {
        HStack(spacing: 10) {
            if let first = state.stripWindows.first?.window {
                Text(first.appName).font(.system(size: 15, weight: .semibold))
            }
            Text("· \(count) windows" + (workspaces > 1 ? " on \(workspaces) workspaces" : ""))
                .font(.system(size: 15))
                .opacity(0.7)
        }
        .foregroundStyle(palette.badgeText)
    }

    /// One workspace: its name and a rule over the card, in the accent where the marking is;
    /// the card with every window at its place, the other apps' faint and taking no input.
    private func card(_ workspace: WorkspaceInfo, _ laid: AeroControlLayout.StripCard, height: CGFloat, ids: [Int], centre: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
        let ink = centre ? palette.accent : palette.badgeText
        return VStack(alignment: .leading, spacing: Self.labelGap) {
            HStack(spacing: 8) {
                Text("Workspace \(workspace.name)")
                    .font(.system(size: 12, weight: centre ? .semibold : .medium))
                    .foregroundStyle(ink.opacity(centre ? 1 : 0.6))
                    .lineLimit(1)
                Rectangle().fill(ink.opacity(centre ? 1 : 0.2)).frame(height: 1)
            }
            .frame(width: laid.span.width, height: Self.labelHeight)
            ZStack(alignment: .topLeading) {
                ForEach(workspace.windows.filter { laid.frames[$0.windowId] != nil }, id: \.windowId) { window in
                    let frame = laid.frames[window.windowId]!
                    if laid.others.contains(window.windowId) {
                        // The rest of the workspace, so the card reads as the whole of it: grey and half
                        // there, with its app's icon. krn.overview's 0.15 vanished on a dark card.
                        tile(window, frame, showsIcon: true).saturation(0).opacity(Self.othersOpacity).allowsHitTesting(false)
                            .offset(x: frame.minX, y: frame.minY)
                    } else {
                        // The key and the hover belong to the window's own frame, so both go on before it is moved there.
                        tile(window, frame)
                            .overlay(alignment: .bottomLeading) { keyCap(ids.firstIndex(of: window.windowId)) }
                            .onHover { if $0 { state.pointStrip(window.windowId, at: NSEvent.mouseLocation) } }
                            .offset(x: frame.minX, y: frame.minY)
                            .zIndex(1)
                    }
                }
            }
            .frame(width: laid.span.width, height: height, alignment: .topLeading)
            .background(shape.fill(palette.badgeFill.opacity(0.35)))
            .clipShape(shape)
        }
    }

    private func tile(_ window: WindowInfo, _ frame: CGRect, showsIcon: Bool = false) -> some View {
        AeroControlAppTile(window: window, metrics: AeroControlMetrics(tileSize: frame.size), filtering: false, showsIcon: showsIcon)
            .frame(width: frame.width, height: frame.height)
    }

    /// The window's key, 1–9 then a–f, in its bottom-left corner.
    @ViewBuilder private func keyCap(_ index: Int?) -> some View {
        if let label = index.flatMap(AppStripModel.keyLabel) {
            Text(label)
                .font(.system(size: 12, weight: .bold, design: .rounded).monospaced())
                .foregroundStyle(palette.badgeText)
                .frame(minWidth: 20, minHeight: 20)
                .background(palette.badgeFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(8)
        }
    }
}
