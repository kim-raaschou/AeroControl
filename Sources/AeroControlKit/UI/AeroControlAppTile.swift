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
    /// Another app's window in the strip: grey and half there, so it is plainly not what you
    /// are choosing, and framed at full strength, so where it stands still reads.
    var faded = false

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
            // Drawn larger than it was taken, the picture is asked for again at this size.
            .onChange(of: [drawnPixels.width, drawnPixels.height, preview?.size.width ?? 0], initial: true) {
                state.wantPicture(window.windowId, pixels: drawnPixels)
            }
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

    /// The pixels the picture fills on screen.
    private var drawnPixels: CGSize { CGSize(width: contentSize.width * displayScale, height: contentSize.height * displayScale) }

    /// The window's own name, centred over the picture it belongs to. Never truncated: a
    /// filter that has narrowed to a handful leaves each tile wide, and the part that tells
    /// two windows apart sits at the front of the title where an ellipsis would land.
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
            .overlay { if faded { outline } }                  // faded with the picture: an outline, not a frame to look at
            .saturation(faded ? 0 : 1)
            .opacity(faded ? Self.fadedOpacity : 1)
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.offset)
            .opacity(isHidden ? 0.45 : 1)
            .overlay(selectionPlate.allowsHitTesting(false))     // on the picture's edge, under the buttons
            .overlay(alignment: .topTrailing) { closeButton }
            .overlay(alignment: .topLeading) { stateBadge }
    }

    /// The plate, and the picture over it once it has landed (the store lands a workspace's
    /// together, in a wave): it fades in, and a picture taken
    /// again fades over the one it replaces rather than swapping in. The key or the icon is on
    /// the plate from the start, so the keys can be read before the pictures are in.
    private var tile: some View {
        let plate = RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
        return ZStack {
            plate.fill(palette.badgeFill.opacity(0.35))
            FadingPicture(image: preview, fade: Self.fade * motion) { image in
                PixelImage(image: image, size: contentSize)
                    .clipShape(plate)
                    // A hairline round the picture: a dark terminal on a dark card otherwise has no edge.
                    .overlay(plate.strokeBorder(palette.cardBorder, lineWidth: 1))
            }
        }
        .overlay(alignment: .bottomLeading) {       // the badge is not clipped with the picture
            if let key {
                keyCap(key.label, marked: key.marked)
            } else if showsIcon, let icon = state.icons[window.bundleId] {
                PixelImage(image: icon, size: CGSize(width: metrics.badgeSize, height: metrics.badgeSize))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(metrics.badgeSize * 0.2)
            }
        }
    }

    /// How much of another app's window shows in the strip: enough to place it, too little to
    /// draw the eye. krn.overview's 0.15 vanished on a dark card; 0.45 drew the eye.
    private static let fadedOpacity: Double = 0.3
    /// How long a picture takes to fade in, or over the one before it.
    private static let fade: Double = 0.6

    /// Focus: a thin accent ring on the picture's edge, with its corners and a soft glow,
    /// matching the focused workspace card's accent border.
    /// A floating window is not in the tiling layout: it lies on top of it. The map already
    /// draws it there, so the tile only has to look raised — a real shadow, no extra outline
    /// competing with the focus ring. Focused floating windows keep both.
    private var shadow: (opacity: Double, radius: CGFloat, offset: CGFloat) {
        if window.isFloating { return (0.5, 12, 5) }
        return (isFocused || faded ? 0 : 0.12, 2, 1)
    }

    /// The one frame a picture wears short of the ring: on the window you came from, and —
    /// faded with its picture — on another app's window in the strip.
    private var outline: some View {
        RoundedRectangle(cornerRadius: plateRadius, style: .continuous)
            .strokeBorder(palette.badgeText.opacity(0.45), lineWidth: 1.5)
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
            outline.frame(width: size.width, height: size.height)
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

/// A tile's picture as it changes. One already there when the tile opens is simply there,
/// from the first frame. One that lands while the tile is open comes into focus from faint and
/// soft; one that replaces another fades in over it, the old staying whole beneath until the new
/// one is all there, so the plate never shows between two pictures.
private struct FadingPicture<Content: View>: View {
    let image: NSImage?
    let fade: Double
    let content: (NSImage) -> Content

    @State private var shown: NSImage?
    @State private var under: NSImage?
    @State private var arrived = true

    init(image: NSImage?, fade: Double, @ViewBuilder content: @escaping (NSImage) -> Content) {
        self.image = image
        self.fade = fade
        self.content = content
        _shown = State(initialValue: image)     // set on appearing instead, the first frame was the plate
    }

    var body: some View {
        ZStack {
            if let under { content(under) }
            // The layer is there before its first picture, so that picture is a change to animate.
            Group { if let shown { content(shown) } else { Color.clear } }
                .opacity(arrived ? 1 : 0)       // only that: grown into place from 90 %, the pixel-exact picture shimmered
                .animation(.smooth(duration: fade), value: arrived)
        }
        .onChange(of: image) { _, new in
            guard let new else { shown = nil; under = nil; return }
            var faint = Transaction()
            faint.disablesAnimations = true
            withTransaction(faint) { under = shown; shown = new; arrived = false }
            // Brought in only once it has been drawn faint: set and animated in one turn, SwiftUI
            // never drew the faint start and the picture snapped in.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(20))
                guard shown === new else { return }
                arrived = true
                try? await Task.sleep(for: .seconds(fade))
                if shown === new { under = nil }
            }
        }
    }
}
