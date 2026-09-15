import AppKit
import Common
import OSLog
import ScreenCaptureKit

private let log = Logger(subsystem: "com.aerocontrol.AeroControl", category: "previews")

public final class NativeApiBridgeAdapter: NativeApiBridge {
    private var iconCache: [String: NSImage] = [:]
    private var closeMonitor: Any?

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

    public func windowCloseSignals() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.closeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
                continuation.yield()
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeCloseMonitor() }
            }
        }
    }

    private func removeCloseMonitor() {
        if let closeMonitor { NSEvent.removeMonitor(closeMonitor) }
        closeMonitor = nil
    }

    // MARK: Window previews (ScreenCaptureKit)

    public var canCapturePreviews: Bool { CGPreflightScreenCaptureAccess() }

    public func requestPreviewAccess() {
        let granted = CGRequestScreenCaptureAccess()
        log.notice("previews: Screen Recording not granted; requested access -> \(granted)")
    }

    /// Captures each window once, sequentially (a handful of ~10-30 ms captures; a task
    /// group would only buy complexity). Off-screen windows parked by AeroSpace still
    /// have content and capture fine. AeroSpace window ids are CGWindowIDs.
    public func windowPreviews(windowIds: [Int], maxSize: CGSize) async -> [Int: NSImage] {
        guard canCapturePreviews else { log.notice("previews: Screen Recording not granted"); return [:] }
        guard !windowIds.isEmpty else { return [:] }
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            log.error("previews: shareable content failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        let wanted = Set(windowIds.map { CGWindowID($0) })
        var result: [Int: NSImage] = [:]
        for window in content.windows where wanted.contains(window.windowID) {
            if let image = await Self.capture(window, maxSize: maxSize) {
                result[Int(window.windowID)] = image
            }
        }
        log.notice("previews: requested \(windowIds.count) matched \(content.windows.filter { wanted.contains($0.windowID) }.count) captured \(result.count)")
        return result
    }

    private static func capture(_ window: SCWindow, maxSize: CGSize) async -> NSImage? {
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return nil }
        let scale = min(maxSize.width / frame.width, maxSize.height / frame.height, 1)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(frame.width * scale * 2))    // 2x: keep previews crisp on Retina
        config.height = max(1, Int(frame.height * scale * 2))
        config.showsCursor = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let cgImage: CGImage
        do {
            cgImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        } catch {
            log.error("previews: capture of window \(window.windowID) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: frame.width * scale, height: frame.height * scale))
    }

    private static func loadIcon(bundleId: String) -> NSImage {
        let original: NSImage
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            original = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            original = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return normalized(original)
    }

    /// Trims an app icon to its opaque artwork and draws it filling the canvas, so every
    /// badge is the same size and sits on the same edge. macOS icons carry a transparent
    /// margin with a soft drop shadow in it; drawn at badge size on a dark ground that
    /// margin reads as a grey rim of uneven width (VS Code, IntelliJ). The alpha scan runs
    /// once per app on a 256 px rasterization; the icon itself is drawn lazily by a drawing
    /// handler at the exact on-screen resolution, so it stays as crisp as the Dock.
    private static func normalized(_ image: NSImage) -> NSImage {
        let canvas: CGFloat = 128, scanPx = 256
        var proposed = NSRect(x: 0, y: 0, width: scanPx, height: scanPx)
        guard let cg = unsafe image.cgImage(forProposedRect: &proposed, context: nil, hints: nil),
              let bounds = opaqueBounds(of: cg) else { return image }
        let scanW = CGFloat(cg.width), scanH = CGFloat(cg.height)
        // Opaque bounds as fractions, in the image's bottom-left point space.
        let fx = bounds.minX / scanW, fw = bounds.width / scanW, fh = bounds.height / scanH
        let fyBottom = 1 - bounds.minY / scanH - fh
        return NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            guard let gctx = NSGraphicsContext.current else { return false }
            gctx.imageInterpolation = .high
            let os = image.size
            let src = CGRect(x: fx * os.width, y: fyBottom * os.height, width: fw * os.width, height: fh * os.height)
            guard src.width > 0, src.height > 0 else { return false }
            let scale = canvas / max(src.width, src.height)
            let w = src.width * scale, h = src.height * scale
            image.draw(in: CGRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h),
                       from: src, operation: .sourceOver, fraction: 1)
            return true
        }
    }

    /// Bounding box of the icon's solid pixels (alpha above half, so soft shadows in the
    /// margin do not count), in the CGImage's top-left coordinate space.
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
        let threshold: UInt8 = 128
        var minX = w, minY = h, maxX = -1, maxY = -1
        for row in 0..<h {
            let rowStart = row * bytesPerRow
            for col in 0..<w where buffer[rowStart + col * 4 + 3] > threshold {
                minX = min(minX, col); maxX = max(maxX, col)
                minY = min(minY, row); maxY = max(maxY, row)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        // The scan buffer is bottom-up; flip Y into top-left space.
        return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

}
