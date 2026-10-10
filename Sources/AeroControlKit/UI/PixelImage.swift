import Common
import SwiftUI

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
