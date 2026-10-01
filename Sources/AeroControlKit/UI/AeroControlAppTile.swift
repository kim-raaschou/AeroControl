import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroDismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.aeroTheme) private var theme
    @Environment(\.aeroMotion) private var motion

    private var palette: AeroControlPalette { theme.palette(for: colorScheme) }
    let window: WindowInfo
    let metrics: AeroControlMetrics
    /// Whether the grid this tile sits in is a filtered result. The panel decides that once,
    /// from what it is drawing — a second answer derived from the query length disagreed with
    /// it on a miss, and captioned every window on a map that had not moved.
    let filtering: Bool
    /// Whether the picture carries its app's icon. Not in the app strip: every tile there is
    /// the same app, and the icon would say the one thing that is already known.
    var showsIcon = true
    /// The strip's key on this window, and whether it is the marked one: drawn where the icon
    /// would be, on the picture's corner.
    var key: (label: String, marked: Bool)?

    @State private var isHovering = false
    @Environment(\.displayScale) private var displayScale

    /// The window's snapshot, fitted into the cell with its own aspect ratio, with the app's
    /// icon badged in its corner; until it lands — or for good, without Screen Recording —
    /// the tile is a plate in the snapshot's shape, and nothing else: an icon standing in for
    /// a picture flashed in whenever a picture went away.
    private var preview: NSImage? { state.previews[window.windowId] }
    /// The ring: AeroSpace's focus on the map, the selected match while filtering.
    private var isFocused: Bool { window.windowId == state.ringWindowId }
    /// The window you came from, while the ring is elsewhere: framed in the text colour so
    /// "where I am" and "where I am going" are both on screen, and never at one place.
    private var isOrigin: Bool { !isFocused && window.windowId == state.model.focusedWindowId }
    /// An app hidden with ⌘H has its windows on no screen; the tile says so by fading.
    private var isHidden: Bool { state.hiddenBundleIds.contains(window.bundleId) }

    /// While a filter is up the title is the point: two windows of one app are told apart by
    /// their title and their picture, and the title is the one that is provably current —
    /// AeroSpace re-reads it from Accessibility on every load. It is drawn rather than left
    /// in the tooltip, which costs a second of holding the mouse still.
    private var showsCaption: Bool {
        filtering && tileSize.height >= AeroControlLayout.captionLane + Self.minPictureHeight
    }

    /// A window without a title is still a window; name it by its app rather than leave the
    /// caption blank.
    private var captionText: String { window.caption }

    /// A caption only earns its lane when the picture under it stays at least this tall;
    /// below that the label would be bigger than the thing it labels.
    private static let minPictureHeight: CGFloat = 92

    private func onFocusWindow() {
        state.send(.action(.focusWindow(window.windowId)))
        dismiss()
    }

    private func onCloseWindow() {
        state.send(.action(.closeWindow(window.windowId)))
    }

    /// Pointing is the selection: Cmd-Q acts on whatever the mouse is over.
    private func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        if hovering { state.hoveredWindowId = window.windowId }
        else if state.hoveredWindowId == window.windowId { state.hoveredWindowId = nil }
    }
    private var plateRadius: CGFloat { AeroControlMetrics.snapshotRadius }
    /// The focus ring lies on the picture's edge, so it has the picture's corners.
    private var ringRadius: CGFloat { plateRadius }
    private var tileSize: CGSize { metrics.tileSize }

    /// The room the picture has: the cell, less the caption's lane when there is one. Every
    /// other size here is derived from this one box, so the ring, the close button and the
    /// picture can never disagree about where the picture is.
    private var pictureBox: CGSize {
        CGSize(width: tileSize.width,
               height: tileSize.height - (showsCaption ? AeroControlLayout.captionLane : 0))
    }

    /// What is actually drawn: the fitted snapshot — sized from the window's measured size
    /// before the picture is in, so the place it lands in is already its shape — or the
    /// whole box when nothing is known about the window.
    private var contentSize: CGSize {
        guard let size = preview?.size ?? state.previewSizes[window.windowId] else { return pictureBox }
        return AeroControlMetrics.pixelSnapped(AeroControlMetrics.fit(size, into: pictureBox), scale: displayScale)
    }

    /// The focus frame hugs the drawn content, not the cell.
    private var plateSize: CGSize { AeroControlMetrics.focusPlateRect(around: contentSize) }

    var body: some View {
        VStack(spacing: AeroControlLayout.captionGap) {
            if showsCaption { caption }
            artwork
        }
            .frame(width: tileSize.width, height: tileSize.height)
            .contentShape(Rectangle())
            .onTapGesture(perform: onFocusWindow)
            .onHover(perform: hoverChanged)
            .help(window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)")
            .draggable(OverviewDragPayload.window(id: window.windowId)) {
                tile
                    .frame(width: contentSize.width, height: contentSize.height)
                    .onAppear { hoverChanged(false) }
            }
    }

    /// The window's own name, centred over the picture it belongs to. Never truncated: a
    /// filter that has narrowed to a handful leaves each tile wide, and the part that tells
    /// two windows apart sits at the front of the title where an ellipsis would land.
    /// The window's key, drawn as a key: ⌘ and its digit in the system's type on a keycap — a
    /// face, a hairline and a lip under it — so it reads as a shortcut and not as another
    /// workspace badge. The marked window's in the accent, as the focused workspace's badge.
    private func keyCap(_ label: String, marked: Bool) -> some View {
        let cap = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(marked ? palette.focusedBadgeText : palette.badgeText)
            .padding(.horizontal, 7)
            .frame(minWidth: AeroControlLayout.badgeSize, minHeight: AeroControlLayout.badgeSize)
            .background(cap.fill(marked ? palette.accent : palette.cardFill ?? Color(nsColor: .controlBackgroundColor)))
            .overlay(cap.strokeBorder(palette.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 0, y: 1.5)
            .padding(metrics.badgeSize * 0.2)
    }

    /// The capture at exactly the pixels it fills, drawn one to one and unfiltered
    /// (`PictureResampler`); scaled by the renderer only when it cannot be had.
    @ViewBuilder private func picture(_ preview: NSImage) -> some View {
        let pixels = CGSize(width: contentSize.width * displayScale, height: contentSize.height * displayScale)
        if let source = preview.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let exact = PictureResampler.picture(source, pixels: pixels) {
            Image(decorative: exact, scale: displayScale).resizable().interpolation(.none)
        } else {
            Image(nsImage: preview).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
        }
    }

    private var caption: some View {
        Text(captionText)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(palette.badgeText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(height: AeroControlLayout.captionTitleHeight)
    }

    /// The picture, its focus ring and the close button — everything the caption is not.
    private var artwork: some View {
        tile
            .frame(width: contentSize.width, height: contentSize.height)
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.offset)
            .opacity(isHidden ? 0.45 : 1)
            .overlay(selectionPlate.allowsHitTesting(false))     // on the picture's edge, under the buttons
            .overlay(alignment: .topTrailing) { closeButton }
            .overlay(alignment: .topLeading) { stateBadge }
    }

    /// The plate, and the picture over it once the overview shows its pictures
    /// (`OverviewStore.revealsPictures`): all of them fade in together, and a picture taken
    /// again fades over the one it replaces rather than swapping in. The key or the icon is on
    /// the plate from the start, so the keys can be read before the pictures are in.
    private var tile: some View {
        let plate = RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
        return ZStack {
            plate.fill(palette.badgeFill.opacity(0.35))
            if let preview, state.revealsPictures {
                picture(preview)
                    .clipShape(plate)
                    // A hairline round the picture: a dark terminal on a dark card otherwise has no edge.
                    .overlay(plate.strokeBorder(palette.cardBorder, lineWidth: 1))
                    .id(ObjectIdentifier(preview))           // a new picture is a new view, fading over the old
                    .transition(Sharpen())
            }
        }
        .animation(.smooth(duration: Self.fade * motion), value: shownPicture)
        .overlay(alignment: .bottomLeading) {       // the badge is not clipped with the picture
            if let key {
                keyCap(key.label, marked: key.marked)
            } else if showsIcon, let icon = state.icons[window.bundleId] {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: metrics.badgeSize, height: metrics.badgeSize)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(metrics.badgeSize * 0.2)
            }
        }
    }

    /// How long a picture takes to come into focus, or over the one before it.
    private static let fade: Double = 0.45
    /// The picture on screen, if any: what the fade follows.
    private var shownPicture: ObjectIdentifier? { state.revealsPictures ? preview.map(ObjectIdentifier.init) : nil }

    /// Focus: a thin accent ring on the picture's edge, with its corners and a soft glow,
    /// matching the focused workspace card's accent border.
    /// A floating window is not in the tiling layout: it lies on top of it. The map already
    /// draws it there, so the tile only has to look raised — a real shadow, no extra outline
    /// competing with the focus ring. Focused floating windows keep both.
    private var shadow: (opacity: Double, radius: CGFloat, offset: CGFloat) {
        if window.isFloating { return (0.5, 12, 5) }
        return (isFocused ? 0 : 0.12, 2, 1)
    }

    @ViewBuilder private var selectionPlate: some View {
        let size = plateSize
        let shape = RoundedRectangle(cornerRadius: ringRadius, style: .continuous)
        if isFocused {
            shape
                .strokeBorder(palette.accent, lineWidth: AeroControlMetrics.focusRingWidth)
                .shadow(color: palette.accent.opacity(0.45), radius: 3)
                .frame(width: size.width, height: size.height)
        } else if isOrigin {
            shape
                .strokeBorder(palette.badgeText.opacity(0.7), lineWidth: 1.5)
                .frame(width: size.width, height: size.height)
        }
    }

    /// A native-fullscreen window wears the glyph macOS uses for it, so a picture that is
    /// the whole screen is read as one.
    @ViewBuilder private var stateBadge: some View {
        if window.isFullscreen, preview != nil {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(palette.badgeText)
                .padding(4)
                .background(palette.badgeFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(6)
        }
    }

    @ViewBuilder private var closeButton: some View {
        if isHovering {
            let diameter: CGFloat = 18
            Button(action: onCloseWindow) {
                Image(systemName: "xmark")
                    .font(.system(size: diameter * 0.45, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: diameter, height: diameter)
                    .background(palette.closeButtonFill, in: Circle())
                    .overlay(Circle().strokeBorder(.separator, lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(6)                                         // inside the snapshot's corner, clear of the focus ring
            .help("Close window")
        }
    }
}

/// A picture coming in: from faint and soft to there and sharp, as a window comes into focus,
/// rather than only fading — the softer of the two to the eye.
private struct Sharpen: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .blur(radius: phase.isIdentity ? 0 : 10)
    }
}
