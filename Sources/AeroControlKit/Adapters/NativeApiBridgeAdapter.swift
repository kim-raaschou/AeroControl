import AppKit
import Common
import OSLog
// ScreenCaptureKit's types are not marked Sendable yet; they are only ever touched on the main actor here.
@unsafe @preconcurrency import ScreenCaptureKit

private let log = Logger(subsystem: "com.aerocontrol.AeroControl", category: "previews")

public final class NativeApiBridgeAdapter: NativeApiBridge {
    public init() {}

    private var iconCache: [String: NSImage] = [:]

    public func appIcon(bundleId: String) -> NSImage {
        if let cached = iconCache[bundleId] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        let icon = Self.largeRepresentation(of: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
        iconCache[bundleId] = icon
        return icon
    }

    /// Keeps only the 256-point representation of a macOS icon (512 pixels on a 2x screen).
    static func largeRepresentation(of image: NSImage) -> NSImage {
        let side: CGFloat = 256
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let rep = image.bestRepresentation(for: rect, context: nil, hints: nil) else { return image }
        let large = NSImage(size: rect.size)
        large.addRepresentation(rep)
        return large
    }

    // MARK: Window previews (ScreenCaptureKit)

    public var canCapturePreviews: Bool { CGPreflightScreenCaptureAccess() }

    public func requestPreviewAccess() {
        let granted = CGRequestScreenCaptureAccess()
        log.notice("previews: Screen Recording not granted; requested access -> \(granted)")
    }

    /// The one system-wide window enumeration a capture needs (~100 ms), started early so it runs
    /// while AeroSpace is being read instead of after.
    private var pendingContent: Task<SCShareableContent?, Never>?
    /// The enumeration `previewSizes` resolved, kept for the capture that follows it.
    private var content: SCShareableContent?

    public func prepareCapture() {
        guard canCapturePreviews else { return }
        content = nil
        pendingContent = Task { @MainActor in await Self.shareableContent() }
    }

    private func resolvedContent() async -> SCShareableContent? {
        if let content { return content }
        if let pending = pendingContent {
            pendingContent = nil
            content = await pending.value
        } else {
            content = await Self.shareableContent()
        }
        return content
    }

    /// The live picture's view, started once the visit's enumeration has the window: not without
    /// Screen Recording, or for a window opened after the summon, and the picture beneath shows.
    public func liveWindow(_ id: Int, pixels: CGSize) -> NSView {
        let view = LiveWindowView()
        Task { unsafe await resolvedContent()?.windows.first { unsafe Int($0.windowID) == id }.map { view.start($0, pixels: pixels) } }
        return view
    }

    /// Read from the window server each time, not from the visit's enumeration: a window resized
    /// while the overview is up — laid out again by AeroSpace, its app getting round to it — kept
    /// its size from the summon there, and was never taken again.
    public func previewSizes(windowIds: [Int]) async -> [Int: CGSize] {
        guard canCapturePreviews else { return [:] }
        let wanted = Set(windowIds)
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.reduce(into: [:]) { sizes, window in
            guard let id = window[kCGWindowNumber as String] as? Int, wanted.contains(id),
                  let bounds = window[kCGWindowBounds as String] as? [String: Double],
                  let width = bounds["Width"], let height = bounds["Height"], width > 1, height > 1 else { return }
            sizes[id] = CGSize(width: width, height: height)
        }
    }

    private static func shareableContent() async -> SCShareableContent? {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            log.error("previews: shareable content failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// How many captures are in flight at once.
    private static let parallelCaptures = 16

    /// Captures each window once, delivering each picture the moment it lands.
    public func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async {
        guard canCapturePreviews else { log.notice("previews: Screen Recording not granted"); return }
        guard !windowIds.isEmpty, var content = await resolvedContent() else { return }
        // The visit's enumeration is kept; a window resized since is enumerated again.
        let sizes = await previewSizes(windowIds: windowIds)
        if content.windows.contains(where: { sizes[Int($0.windowID)].map { [frame = $0.frame.size] in $0 != frame } ?? false }),
           let fresh = await Self.shareableContent() {
            self.content = fresh
            content = fresh
        }
        // Taken in the order asked, the overview's reading order, so its first cards are in first.
        let byId = Dictionary(content.windows.map { (Int($0.windowID), $0) }) { first, _ in first }
        let windows = windowIds.compactMap { byId[$0] }
        let started = ContinuousClock.now
        let captured = await withTaskGroup(of: (Int, NSImage)?.self, returning: Int.self) { group in
            var captured = 0
            var inFlight = 0
            for window in windows {
                // One finishes, one starts: the window server sees a steady few, never all.
                if inFlight == Self.parallelCaptures, let landed = await group.next() {
                    if let (id, image) = landed { deliver(id, image); captured += 1 }
                    inFlight -= 1
                }
                // SCWindow is not Sendable; it is handed to exactly one child task and never
                // touched here again, which is the move the checker cannot see.
                nonisolated(unsafe) let window = window
                let id = unsafe Int(window.windowID)
                group.addTask { unsafe await Self.capture(window, maxSize: maxSize).map { (id, $0) } }
                inFlight += 1
            }
            for await landed in group {
                if let (id, image) = landed { deliver(id, image); captured += 1 }
            }
            return captured
        }
        let ms = (ContinuousClock.now - started) / .milliseconds(1)
        log.notice("previews: requested \(windowIds.count) captured \(captured) in \(Int(ms)) ms")
    }

    private static func capture(_ window: SCWindow, maxSize: CGSize) async -> NSImage? {
        let frame = window.frame
        guard frame.width > 1, frame.height > 1 else { return nil }
        let scale = min(maxSize.width / frame.width, maxSize.height / frame.height, 1)
        let config = SCStreamConfiguration()
        // `maxSize` is in pixels, not points.
        config.width = max(1, Int(frame.width * scale))
        config.height = max(1, Int(frame.height * scale))
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
}
