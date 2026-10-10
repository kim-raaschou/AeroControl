import Common
import SwiftUI

/// An image drawn at exactly the screen's pixels it covers, one to one and unfiltered — a
/// window's picture or an app's icon. Left to the renderer, a 256-pixel icon shrunk to a 22-point
/// badge on a 1x screen came out grainy, as the pictures had. The size is rounded to whole
/// pixels; scaled by the renderer only when no exact copy can be had.
struct PixelImage: View {
    let image: NSImage
    let size: CGSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let snapped = AeroControlMetrics.pixelSnapped(size, scale: displayScale)
        let pixels = CGSize(width: snapped.width * displayScale, height: snapped.height * displayScale)
        Group {
            if let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
               let exact = PictureResampler.picture(source, pixels: pixels) {
                Image(decorative: exact, scale: displayScale).resizable().interpolation(.none)
            } else {
                Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: snapped.width, height: snapped.height)
    }
}
