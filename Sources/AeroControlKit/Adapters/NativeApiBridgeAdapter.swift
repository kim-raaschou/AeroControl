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
        return largeRepresentation(of: original)
    }

    /// Keeps only the 256 px representation of a macOS icon. Left to itself, AppKit picks
    /// the representation nearest the drawn size, and for a 28 pt badge on a 1x display that
    /// is the 32 px one, which for pre-Tahoe icons (VS Code, IntelliJ) carries macOS 26's
    /// grey wrapper rim and looks smaller than its neighbours. Downscaling the large
    /// representation with high interpolation gives the same clean artwork at every size
    /// and on every display scale.
    private static func largeRepresentation(of image: NSImage) -> NSImage {
        let side: CGFloat = 256
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let rep = image.bestRepresentation(for: rect, context: nil, hints: nil) else { return image }
        let large = NSImage(size: rect.size)
        large.addRepresentation(rep)
        return large
    }

}
