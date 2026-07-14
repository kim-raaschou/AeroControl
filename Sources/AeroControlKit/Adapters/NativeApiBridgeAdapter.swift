import AppKit
import Common

public final class NativeApiBridgeAdapter: NativeApiBridge {
    private var iconCache: [String: NSImage] = [:]
    private static let iconPointSize: CGFloat = 128

    public init() {}

    public func appIcon(bundleId: String) -> NSImage {
        if let cached = iconCache[bundleId] {
            return cached
        }
        let icon = Self.loadIcon(bundleId: bundleId)
        iconCache[bundleId] = icon
        return icon
    }

    public func appTerminations() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let terminations = NSWorkspace.shared.notificationCenter
                    .notifications(named: NSWorkspace.didTerminateApplicationNotification)
                for await _ in terminations {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func loadIcon(bundleId: String) -> NSImage {
        let original: NSImage
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            original = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            original = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return normalized(original, points: iconPointSize)
    }

    /// Trims each app icon to its opaque artwork and rescales every icon to the same
    /// fill fraction, so the strip reads as an even row.
    ///
    /// macOS app icons carry wildly different built-in padding: an Apple-grid app
    /// (Messages, Mail) nearly fills its canvas, while Electron/JetBrains apps (VS
    /// Code, IntelliJ) centre a much smaller glyph in a sea of transparency. Showing
    /// the raw icons makes those apps look tiny next to their neighbours. We composite
    /// once — finding the opaque bounds, then drawing that region scaled to fill the
    /// tile, centred — with interpolation forced to `.high`
    /// so the single downscale from the source rep stays crisp on any display.
    private static func normalized(_ image: NSImage, points pt: CGFloat) -> NSImage {
        // Find the opaque artwork bounds *once* — as fractions of the source image — by
        // scanning a moderate rasterization. The icon itself is then drawn lazily, at the
        // exact on-screen resolution, by a drawing handler: macOS picks the best-matching
        // native representation and scales it in a single high-quality step, so the strip
        // stays as crisp as the Dock on any display scale (no fixed-bitmap double resample).
        let scanPx = 256
        var proposed = NSRect(x: 0, y: 0, width: scanPx, height: scanPx)
        guard let cg = unsafe image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let bounds = opaqueBounds(of: cg) else {
            return image
        }
        let scanW = CGFloat(cg.width), scanH = CGFloat(cg.height)
        // Opaque bounds as fractions, converted to the image's bottom-left point space
        // (what `NSImage.draw(in:from:)` expects for a non-flipped image).
        let fx = bounds.minX / scanW
        let fw = bounds.width / scanW
        let fh = bounds.height / scanH
        let fyBottom = 1 - (bounds.minY / scanH) - fh

        let out = NSImage(size: NSSize(width: pt, height: pt), flipped: false) { _ in
            guard let gctx = NSGraphicsContext.current else { return false }
            gctx.imageInterpolation = .high
            let os = image.size
            guard os.width > 0, os.height > 0 else { return false }
            let contentW = fw * os.width
            let contentH = fh * os.height
            guard contentW > 0, contentH > 0 else { return false }
            let src = CGRect(x: fx * os.width, y: fyBottom * os.height, width: contentW, height: contentH)
            let scale = pt / max(contentW, contentH)
            let w = contentW * scale
            let h = contentH * scale
            image.draw(
                in: CGRect(x: (pt - w) / 2, y: (pt - h) / 2, width: w, height: h),
                from: src, operation: .sourceOver, fraction: 1
            )
            return true
        }
        return out
    }

    /// Finds the bounding box of an icon's non-transparent pixels, returned in the
    /// CGImage's top-left crop coordinate space (ready for `CGImage.cropping(to:)`).
    private static func opaqueBounds(of cg: CGImage) -> CGRect? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        let bytesPerRow = w * 4
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * h)
        let made: Bool = unsafe buffer.withUnsafeMutableBytes { raw in
            guard let ctx = unsafe CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard made else { return nil }

        let threshold: UInt8 = 12
        var minX = w, minY = h, maxX = -1, maxY = -1
        for row in 0..<h {
            let rowStart = row * bytesPerRow
            for col in 0..<w where buffer[rowStart + col * 4 + 3] > threshold {
                if col < minX { minX = col }
                if col > maxX { maxX = col }
                if row < minY { minY = row }
                if row > maxY { maxY = row }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // The scan buffer is bottom-up (CGContext origin); flip Y into the top-left
        // space that `CGImage.cropping(to:)` expects.
        return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    }
}
