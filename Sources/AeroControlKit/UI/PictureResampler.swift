import Accelerate
import Common
import CoreGraphics
import Foundation
import SwiftUI

/// A capture scaled once, with vImage's high-quality (Lanczos) resampling, to exactly the
/// pixels a tile draws it in. Drawn one to one and unfiltered, it is as sharp as the screen
/// allows; left to the renderer, every frame shrank it with a bilinear filter, and a terminal
/// shrunk threefold came out grainy.
@MainActor enum PictureResampler {
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 128          // every tile's picture and icon, each at its size
        return cache
    }()
    /// The cache's keys by the picture they were scaled from, so a picture taken again takes its
    /// copies with it: they were kept for nothing, and the key is the picture's address, which a
    /// new picture can be given once the old one is gone.
    private static var keysBySource: [ObjectIdentifier: [NSString]] = [:]

    /// `image` at `pixels`; the image itself when it already is that size, nil for no pixels.
    static func picture(_ image: CGImage, pixels: CGSize) -> CGImage? {
        let width = Int(pixels.width.rounded()), height = Int(pixels.height.rounded())
        guard width > 0, height > 0 else { return nil }
        if image.width == width, image.height == height { return image }
        let source = ObjectIdentifier(image)
        let key = "\(source.hashValue) \(width)x\(height)" as NSString
        if let kept = cache.object(forKey: key) { return kept }
        guard let scaled = resample(image, width: width, height: height) else { return nil }
        cache.setObject(scaled, forKey: key)
        keysBySource[source, default: []].append(key)
        return scaled
    }

    /// A picture about to be replaced: its scaled copies go before it does.
    static func forget(_ picture: NSImage?) {
        let image = picture?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        (image.flatMap { keysBySource.removeValue(forKey: ObjectIdentifier($0)) } ?? []).forEach(cache.removeObject(forKey:))
    }

    /// Everything kept: the captures it was made from are gone, and the next summon takes new ones.
    static func forget() {
        cache.removeAllObjects()
        keysBySource = [:]
    }

    private static func resample(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard var format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32,
                                                colorSpace: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
              var source = try? vImage_Buffer(cgImage: image, format: format),
              var target = try? vImage_Buffer(width: width, height: height, bitsPerPixel: 32) else { return nil }
        defer { source.free(); target.free() }
        guard vImageScale_ARGB8888(&source, &target, nil, vImage_Flags(kvImageHighQualityResampling)) == kvImageNoError else { return nil }
        return try? target.createCGImage(format: format)
    }
}

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
