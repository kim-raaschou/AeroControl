import AppKit

/// A capture scaled once, with Core Graphics' high-quality interpolation, to exactly the
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

    /// Drawn straight into a bitmap of the tile's size: no copy of the capture unpacked first,
    /// which on a Retina screen was 2 MB a picture, freed but kept by the allocator.
    private static func resample(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
