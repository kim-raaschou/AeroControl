import SwiftUI
import Common

struct AeroControlAppTile: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look

    let tile: OverviewScene.Tile
    let tiles: Namespace.ID

    @State private var isHovering = false
    @Environment(\.displayScale) private var displayScale

    private var preview: CGImage? { state.pictures.previews[tile.window.windowId] }
    private func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        if hovering { state.point(tile.window.windowId, at: NSEvent.mouseLocation) }
    }
    private var plate: RoundedRectangle { RoundedRectangle(cornerRadius: AeroControlMetrics.snapshotRadius, style: .continuous) }
    private var badgeSize: CGFloat { AeroControlMetrics.badgeSize(width: tile.frame.width) }

    private var contentSize: CGSize {
        AeroControlMetrics.pixelSnapped(tile.picture, scale: displayScale)
    }

    var body: some View {
        if look.surface == .map {
            face.draggable(OverviewDragPayload.window(id: tile.window.windowId)) {
                stack
                    .frame(width: contentSize.width, height: contentSize.height)
                    .onAppear { hoverChanged(false) }
            }
        } else {
            face
        }
    }

    private var face: some View {
        VStack(spacing: AeroControlLayout.captionGap) {
            if tile.captioned { caption }
            artwork
        }
            .frame(width: tile.frame.width, height: tile.frame.height)
            .matchedGeometryEffect(id: tile.window.windowId, in: tiles)
            .contentShape(Rectangle())
            .onTapGesture { state.send(.action(.focusWindow(tile.window.windowId))) }
            .onHover(perform: hoverChanged)
            .help(tile.window.title.isEmpty ? tile.window.appName : "\(tile.window.appName) — \(tile.window.title)")
    }

    private var caption: some View {
        Text(tile.window.caption)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(look.palette.badgeText)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(height: AeroControlLayout.captionTitleHeight)
    }

    private var artwork: some View {
        stack
            .frame(width: contentSize.width, height: contentSize.height)
            .overlay { if tile.faded { outline } }
            .saturation(tile.faded ? 0 : 1)
            .opacity(tile.faded ? Self.fadedOpacity : 1)
            .shadow(color: .black.opacity(shadow.opacity), radius: shadow.radius, y: shadow.offset)
            .opacity(tile.window.isHidden ? 0.45 : 1)
            .overlay(selectionPlate.allowsHitTesting(false))
            .overlay(alignment: .topTrailing) { closeButton }
            .overlay(alignment: .topLeading) { stateBadge }
    }

    private var stack: some View {
        ZStack {
            plate.fill(look.palette.badgeFill.opacity(0.35))
            FadingPicture(image: preview, fade: Self.fade * look.motion) { image in
                let shape = CGSize(width: image.width, height: image.height), foreign = !AeroControlLayout.sameShape(shape, contentSize, within: 0.1)
                PixelImage(image: Image(decorative: image, scale: displayScale), size: foreign ? AeroControlMetrics.fit(shape, into: contentSize) : AeroControlMetrics.cover(shape, into: contentSize))
                    .frame(width: contentSize.width, height: contentSize.height)
                    .clipShape(plate)
                    .overlay(plate.strokeBorder(look.palette.cardBorder, lineWidth: 1))
            }
            if tile.ringed {
                LivePicture { state.pictures.live(tile.window.windowId, pixels: CGSize(width: contentSize.width * displayScale, height: contentSize.height * displayScale)) }
                    .frame(width: contentSize.width, height: contentSize.height)
                    .clipShape(plate)
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            PixelImage(image: Image(nsImage: state.pictures.icon(for: tile.window.bundleId)), size: CGSize(width: badgeSize, height: badgeSize))
                .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                .padding(badgeSize * 0.2)
        }
    }

    private static let fadedOpacity: Double = 0.3
    private static let fade: Double = 0.6

    private var shadow: (opacity: Double, radius: CGFloat, offset: CGFloat) {
        if tile.window.isFloating { return (0.5, 12, 5) }
        return (tile.ringed || tile.faded ? 0 : 0.12, 2, 1)
    }

    private var outline: some View {
        plate.strokeBorder(look.palette.badgeText.opacity(0.45), lineWidth: 1.5)
    }

    @ViewBuilder private var selectionPlate: some View {
        if tile.ringed {
            plate.strokeBorder(look.palette.accent, lineWidth: AeroControlMetrics.focusRingWidth(scale: displayScale))
        } else if tile.origin {
            outline
        }
    }

    @ViewBuilder private var stateBadge: some View {
        if tile.window.isFullscreen, preview != nil {
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
            Button { state.send(.action(.closeWindow(tile.window.windowId))) } label: {
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
    let image: CGImage?
    let fade: Double
    @ViewBuilder let content: (CGImage) -> Content

    var body: some View {
        ZStack { if let image { content(image).id(ObjectIdentifier(image)).transition(.opacity) } }
            .animation(.smooth(duration: fade), value: image.map(ObjectIdentifier.init))
    }
}

private struct LivePicture: NSViewRepresentable {
    let make: () -> NSView
    func makeNSView(context: Context) -> NSView { make() }
    func updateNSView(_ view: NSView, context: Context) {}
}
