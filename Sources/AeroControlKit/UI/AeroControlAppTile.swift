import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look

    let window: WindowInfo
    /// The drawn tile: picture plus caption lane, when there is one, as `TilePacker` placed it.
    let size: CGSize
    /// Whether the grid this tile sits in is a filtered result. The panel decides that once,
    /// from what it is drawing — a second answer derived from the query length disagreed with
    /// it on a miss, and captioned every window on a map that had not moved.
    let filtering: Bool
    /// The strip's key on this window, and whether it is the marked one: drawn where the icon
    /// is otherwise, on the picture's corner. A window that has a key does without its icon:
    /// every window with one is the strip's app, and the icon would say what is already known.
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
    /// The ring: AeroSpace's focus on the map until an arrow moves it, the selected match while filtering.
    private var isFocused: Bool { window.windowId == state.ringWindowId }
    /// The window you came from, while the ring is elsewhere: framed in the text colour so
    /// "where I am" and "where I am going" are both on screen, and never at one place.
    private var isOrigin: Bool { !isFocused && window.windowId == state.model.focusedWindowId }

    /// While a filter is up the title is the point: two windows of one app are told apart by
    /// their title and their picture, and the title is the one that is provably current —
    /// AeroSpace re-reads it from Accessibility on every load. It is drawn rather than left
    /// in the tooltip, which costs a second of holding the mouse still. A window whose size is
    /// not known has no picture coming — without Screen Recording none has — so its title is all
    /// there is to tell it by, filter or not.
    private var showsCaption: Bool {
        (filtering || state.previewSizes[window.windowId] == nil) && size.height >= AeroControlLayout.captionLane + Self.minPictureHeight
    }

    /// A caption only earns its lane when the picture under it stays at least this tall;
    /// below that the label would be bigger than the thing it labels.
    private static let minPictureHeight: CGFloat = 92

    private func hoverChanged(_ hovering: Bool) { isHovering = hovering }
    /// The plate, the picture and the ring on its edge share these corners.
    private var plate: RoundedRectangle { RoundedRectangle(cornerRadius: AeroControlMetrics.snapshotRadius, style: .continuous) }
    private var badgeSize: CGFloat { AeroControlMetrics.badgeSize(width: size.width) }

    /// The room the picture has: the cell, less the caption's lane when there is one. Every
    /// other size here is derived from this one box, so the ring, the close button and the
    /// picture can never disagree about where the picture is.
    private var pictureBox: CGSize {
        CGSize(width: size.width, height: size.height - (showsCaption ? AeroControlLayout.captionLane : 0))
    }

    /// What is actually drawn: the fitted snapshot — sized from the window's measured size
    /// before the picture is in, so the place it lands in is already its shape — or the
    /// whole box when nothing is known about the window.
    private var contentSize: CGSize {
        guard let size = preview?.size ?? state.previewSizes[window.windowId] else { return pictureBox }
        return AeroControlMetrics.pixelSnapped(AeroControlMetrics.fit(size, into: pictureBox), scale: displayScale)
    }

    /// On the map a tile is dragged onto another card to move its window; the strip has no card to
    /// drop on, so there it is not dragged at all.
    var body: some View {
        if state.strip == nil {
            face.draggable(OverviewDragPayload.window(id: window.windowId)) {
                tile
                    .frame(width: contentSize.width, height: contentSize.height)
                    .onAppear { hoverChanged(false) }
            }
        } else {
            face
        }
    }

    private var face: some View {
        VStack(spacing: AeroControlLayout.captionGap) {
            if showsCaption { caption }
            artwork
        }
            .frame(width: size.width, height: size.height)
            // Drawn larger than it was taken, the picture is asked for again at this size.
            .onChange(of: [drawnPixels.width, drawnPixels.height, preview?.size.width ?? 0], initial: true) {
                state.wantPicture(window.windowId, pixels: drawnPixels)
            }
            .contentShape(Rectangle())
            .onTapGesture { state.send(.action(.focusWindow(window.windowId))) }
            .onHover(perform: hoverChanged)
            .help(window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)")
    }

    /// The window's key, drawn as a key: ⌘ and its digit in the system's type on a keycap — a
    /// face, a hairline and a lip under it — so it reads as a shortcut and not as another
    /// workspace badge. The marked window's in the accent, as the focused workspace's badge.
    private func keyCap(_ label: String, marked: Bool) -> some View {
        let cap = RoundedRectangle(cornerRadius: 5, style: .continuous)
        return Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(marked ? look.palette.focusedBadgeText : look.palette.badgeText)
            .padding(.horizontal, 7)
            .frame(minWidth: AeroControlLayout.badgeSize, minHeight: AeroControlLayout.badgeSize)
            .background(cap.fill(marked ? look.palette.accent : look.palette.cardFill ?? Color(nsColor: .controlBackgroundColor)))
            .overlay(cap.strokeBorder(look.palette.cardBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 0, y: 1.5)
            .padding(badgeSize * 0.2)
    }

    /// The pixels the picture fills on screen.
    private var drawnPixels: CGSize { CGSize(width: contentSize.width * displayScale, height: contentSize.height * displayScale) }

    /// The window's own name, centred over the picture it belongs to. Never truncated: a
    /// filter that has narrowed to a handful leaves each tile wide, and the part that tells
    /// two windows apart sits at the front of the title where an ellipsis would land.
    private var caption: some View {
        Text(window.caption)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(look.palette.badgeText)
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
            .opacity(window.isHidden ? 0.45 : 1)            // minimized, or its app hidden: on no screen
            .overlay(selectionPlate.allowsHitTesting(false))     // on the picture's edge, under the buttons
            .overlay(alignment: .topTrailing) { closeButton }
            .overlay(alignment: .topLeading) { stateBadge }
    }

    /// The plate, and the picture over it once it has landed (the store lands a workspace's
    /// together, in a wave): it fades in, and a picture taken
    /// again fades over the one it replaces rather than swapping in. The key or the icon is on
    /// the plate from the start, so the keys can be read before the pictures are in.
    private var tile: some View {
        ZStack {
            plate.fill(look.palette.badgeFill.opacity(0.35))
            FadingPicture(image: preview, fade: Self.fade * look.motion) { image in
                PixelImage(image: image, size: contentSize)
                    .clipShape(plate)
                    // A hairline round the picture: a dark terminal on a dark card otherwise has no edge.
                    .overlay(plate.strokeBorder(look.palette.cardBorder, lineWidth: 1))
            }
            if isFocused {                                   // the window under the ring, live
                LivePicture(windowId: window.windowId, pixels: drawnPixels, bridge: state.nativeSystem as? NativeApiBridgeAdapter)
                    .frame(width: contentSize.width, height: contentSize.height)
                    .clipShape(plate)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {       // the badge is not clipped with the picture
            if let key {
                keyCap(key.label, marked: key.marked)
            } else {
                PixelImage(image: state.icon(for: window.bundleId), size: CGSize(width: badgeSize, height: badgeSize))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(badgeSize * 0.2)
            }
        }
    }

    /// How much of another app's window shows in the strip: enough to place it, too little to
    /// draw the eye. krn.overview's 0.15 vanished on a dark card; 0.45 drew the eye.
    private static let fadedOpacity: Double = 0.3
    /// How long a picture takes to fade in, or over the one before it.
    private static let fade: Double = 0.6

    /// Focus: a thin accent ring on the picture's edge, with its corners. Sharp: a glow round it
    /// made it read wide and soft.
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
        plate.strokeBorder(look.palette.badgeText.opacity(0.45), lineWidth: 1.5)
    }

    /// On the picture's edge, not round it: windows drawn at AeroSpace's gaps are 3 to 6 points
    /// apart on a card, and a ring outside the picture ran into the neighbour. Laid over the
    /// picture, it has the picture's size.
    @ViewBuilder private var selectionPlate: some View {
        if isFocused {
            plate.strokeBorder(look.palette.accent, lineWidth: AeroControlMetrics.focusRingWidth(scale: displayScale))
        } else if isOrigin {
            outline
        }
    }

    /// A window AeroSpace holds fullscreen wears the glyph macOS uses for fullscreen, so a picture that is
    /// the whole screen is read as one.
    @ViewBuilder private var stateBadge: some View {
        if window.isFullscreen, preview != nil {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(look.palette.badgeText)
                .padding(4)
                .background(look.palette.badgeFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(6)
        }
    }

    /// On the map only: the strip is for choosing, and a window closed there moved AeroSpace's focus.
    @ViewBuilder private var closeButton: some View {
        if isHovering, state.strip == nil {
            let diameter: CGFloat = 18
            Button { state.send(.action(.closeWindow(window.windowId))) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: diameter * 0.45, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: diameter, height: diameter)
                    .background(look.palette.closeButtonFill, in: Circle())
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

/// The window under the ring as it changes (`LiveWindowView`), over its picture: one view per
/// window, started as it is made from the bridge's own enumeration, stopped as it goes.
private struct LivePicture: NSViewRepresentable {
    let windowId: Int
    let pixels: CGSize
    let bridge: NativeApiBridgeAdapter?

    func makeNSView(context: Context) -> LiveWindowView {
        let view = LiveWindowView()
        Task { await bridge?.window(windowId).map { view.start($0, pixels: pixels) } }
        return view
    }
    func updateNSView(_ view: LiveWindowView, context: Context) {}
    static func dismantleNSView(_ view: LiveWindowView, coordinator: ()) { view.stop() }
}
