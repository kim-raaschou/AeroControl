import Common
import SwiftUI

struct PixelImage: View {
    let image: Image
    let size: CGSize
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let snapped = AeroControlMetrics.pixelSnapped(size, scale: displayScale)
        image.resizable().interpolation(.high).frame(width: snapped.width, height: snapped.height)
    }
}
