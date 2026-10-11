import AppKit

@MainActor enum PictureResampler {
    private static let cache: NSCache<NSString, CGImage> = {
        let cache = NSCache<NSString, CGImage>()
        cache.countLimit = 128
        return cache
    }()
    private static var keysBySource: [ObjectIdentifier: [NSString]] = [:]

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

    static func forget(_ picture: NSImage?) {
        let image = picture?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        (image.flatMap { keysBySource.removeValue(forKey: ObjectIdentifier($0)) } ?? []).forEach(cache.removeObject(forKey:))
    }

    static func forget() {
        cache.removeAllObjects()
        keysBySource = [:]
    }

    private static func resample(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)
        context?.interpolationQuality = .high
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}
