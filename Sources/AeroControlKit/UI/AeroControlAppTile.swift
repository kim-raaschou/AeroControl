import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look

    let window: WindowInfo
    let size: CGSize
    let filtering: Bool
    let tiles: Namespace.ID
    var key: (label: String, marked: Bool)?
    var faded = false

    @State private var isHovering = false
    @Environment(\.displayScale) private var displayScale

    private var preview: NSImage? { state.pictures.previews[window.windowId] }
    private var isFocused: Bool { window.windowId == state.ringWindowId }
    private var isOrigin: Bool { !isFocused && window.windowId == state.model.focusedWindowId }

    private var showsCaption: Bool {
        (filtering || state.pictures.sizes[window.windowId] == nil) && size.height >= AeroControlLayout.captionLane + Self.minPictureHeight
    }

    private static let minPictureHeight: CGFloat = 92

    private func hoverChanged(_ hovering: Bool) { isHovering = hovering }
    private var plate: RoundedRectangle { RoundedRectangle(cornerRadius: AeroControlMetrics.snapshotRadius, style: .continuous) }
    private var badgeSize: CGFloat { AeroControlMetrics.badgeSize(width: size.width) }

    private var pictureBox: CGSize {
        CGSize(width: size.width, height: size.height - (showsCaption ? AeroControlLayout.captionLane : 0))
    }

    private var contentSize: CGSize { AeroControlMetrics.pixelSnapped(pictureBox, scale: displayScale) }

    var body: some View {
        if look.surface == .map {
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
            .matchedGeometryEffect(id: window.windowId, in: tiles)
            .onChange(of: [drawnPixels.width, drawnPixels.height, preview?.size.width ?? 0], initial: true) {
                state.pictures.want(window.windowId, pixels: preview.map { AeroControlMetrics.cover($0.size, into: drawnPixels) } ?? drawnPixels)
            }
            .contentShape(Rectangle())
            .onTapGesture { state.send(.action(.focusWindow(window.windowId))) }
            .onHover(perform: hoverChanged)
            .help(window.title.isEmpty ? window.appName : "\(window.appName) — \(window.title)")
    }

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

    private var drawnPixels: CGSize { CGSize(width: contentSize.width * displayScale, height: contentSize.height * displayScale) }

    private var caption: some View {
        Text(window.caption)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(look.palette.badgeText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(height: AeroControlLayout.captionTitleHeight)
    }

    private var artwork: some View {
        tile
            .frame(width: contentSize.width, height: contentSize.height)
            .overlay { if faded { outline } }
            .saturation(faded ? 0 : 1)
            .opacity(faded ? Self.fadedOpacity : 1)
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.offset)
            .opacity(window.isHidden ? 0.45 : 1)
            .overlay(selectionPlate.allowsHitTesting(false))
            .overlay(alignment: .topTrailing) { closeButton }
            .overlay(alignment: .topLeading) { stateBadge }
    }

    private var tile: some View {
        ZStack {
            plate.fill(look.palette.badgeFill.opacity(0.35))
            FadingPicture(image: preview, fade: Self.fade * look.motion) { image in
                PixelImage(image: image, size: AeroControlMetrics.cover(image.size, into: contentSize))
                    .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                    .clipShape(plate)
                    .overlay(plate.strokeBorder(look.palette.cardBorder, lineWidth: 1))
            }
            if isFocused {
                LivePicture { state.pictures.live(window.windowId, pixels: drawnPixels) }
                    .frame(width: contentSize.width, height: contentSize.height)
                    .clipShape(plate)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let key {
                keyCap(key.label, marked: key.marked)
            } else {
                PixelImage(image: state.pictures.icon(for: window.bundleId), size: CGSize(width: badgeSize, height: badgeSize))
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .padding(badgeSize * 0.2)
            }
        }
    }

    private static let fadedOpacity: Double = 0.3
    private static let fade: Double = 0.6

    private var shadow: (opacity: Double, radius: CGFloat, offset: CGFloat) {
        if window.isFloating { return (0.5, 12, 5) }
        return (isFocused || faded ? 0 : 0.12, 2, 1)
    }

    private var outline: some View {
        plate.strokeBorder(look.palette.badgeText.opacity(0.45), lineWidth: 1.5)
    }

    @ViewBuilder private var selectionPlate: some View {
        if isFocused {
            plate.strokeBorder(look.palette.accent, lineWidth: AeroControlMetrics.focusRingWidth(scale: displayScale))
        } else if isOrigin {
            outline
        }
    }

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

    @ViewBuilder private var closeButton: some View {
        if isHovering, look.surface == .map {
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
            .padding(6)
            .help("Close window")
        }
    }
}

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
        _shown = State(initialValue: image)
    }

    var body: some View {
        ZStack {
            if let under { content(under) }
            Group { if let shown { content(shown) } else { Color.clear } }
                .opacity(arrived ? 1 : 0)
                .animation(.smooth(duration: fade), value: arrived)
        }
        .onChange(of: image) { _, new in
            guard let new else { shown = nil; under = nil; return }
            var faint = Transaction()
            faint.disablesAnimations = true
            withTransaction(faint) { under = shown; shown = new; arrived = false }
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

private struct LivePicture: NSViewRepresentable {
    let make: () -> NSView
    func makeNSView(context: Context) -> NSView { make() }
    func updateNSView(_ view: NSView, context: Context) {}
}
