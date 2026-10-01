import Accelerate
import CoreGraphics
import Foundation

/// A capture scaled once, with vImage's high-quality (Lanczos) resampling, to exactly the
/// pixels a tile draws it in. Drawn one to one and unfiltered, it is as sharp as the screen
/// allows; left to the renderer, every frame shrank it with a bilinear filter, and a terminal
/// shrunk threefold came out grainy.
@MainActor enum PictureResampler {
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 64
        return cache
    }()

    /// `image` at `pixels`; the image itself when it already is that size, nil for no pixels.
    static func picture(_ image: CGImage, pixels: CGSize) -> CGImage? {
        let width = Int(pixels.width.rounded()), height = Int(pixels.height.rounded())
        guard width > 0, height > 0 else { return nil }
        if image.width == width, image.height == height { return image }
        let key = "\(ObjectIdentifier(image).hashValue) \(width)x\(height)" as NSString
        if let kept = cache.object(forKey: key) { return kept }
        guard let scaled = resample(image, width: width, height: height) else { return nil }
        cache.setObject(scaled, forKey: key)
        return scaled
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
