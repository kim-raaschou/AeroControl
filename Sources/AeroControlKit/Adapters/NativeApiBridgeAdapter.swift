import AppKit
import Common
import OSLog
// ScreenCaptureKit's types are not marked Sendable yet; they are only ever touched on the main actor here.
@preconcurrency import ScreenCaptureKit

private let log = Logger(subsystem: "com.aerocontrol.AeroControl", category: "previews")

public final class NativeApiBridgeAdapter: NativeApiBridge {
    private var iconCache: [String: NSImage] = [:]

    public init() {}

    public func appIcon(bundleId: String) -> NSImage {
        if let cached = iconCache[bundleId] {
            return cached
        }
        let icon = Self.loadIcon(bundleId: bundleId)
        iconCache[bundleId] = icon
        return icon
    }

    // MARK: Window previews (ScreenCaptureKit)

    public var canCapturePreviews: Bool { CGPreflightScreenCaptureAccess() }

    public func requestPreviewAccess() {
        let granted = CGRequestScreenCaptureAccess()
        log.notice("previews: Screen Recording not granted; requested access -> \(granted)")
    }

    /// The one system-wide window enumeration a capture needs (~100 ms), started early so it
    /// runs while AeroSpace is being read instead of after.
    private var pendingContent: Task<SCShareableContent?, Never>?
    /// The enumeration `previewSizes` resolved, kept for the capture that follows it.
    private var content: SCShareableContent?

    public func prepareCapture() {
        guard canCapturePreviews else { return }
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

    public func previewSizes(windowIds: [Int]) async -> [Int: CGSize] {
        guard canCapturePreviews, let content = await resolvedContent() else { return [:] }
        let wanted = Set(windowIds.map { CGWindowID($0) })
        return Dictionary(uniqueKeysWithValues: content.windows.lazy
            .filter { wanted.contains($0.windowID) && $0.frame.width > 1 && $0.frame.height > 1 }
            .map { (Int($0.windowID), $0.frame.size) })
    }

    private static func shareableContent() async -> SCShareableContent? {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            log.error("previews: shareable content failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// How many captures are in flight at once. They are independent and the window
    /// server overlaps them, with diminishing returns: 18 windows took 243 ms one at a
    /// time, 200 ms six at a time, ~150 ms sixteen at a time.
    private static let parallelCaptures = 16

    /// Captures each window once, delivering each picture the moment it lands. Off-screen
    /// windows parked by AeroSpace still have content and capture fine. AeroSpace window
    /// ids are CGWindowIDs.
    public func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async {
        guard canCapturePreviews else { log.notice("previews: Screen Recording not granted"); return }
        guard !windowIds.isEmpty, let content = await resolvedContent() else { return }
        self.content = nil                                   // one summon, one enumeration
        let wanted = Set(windowIds.map { CGWindowID($0) })
        let windows = content.windows.filter { wanted.contains($0.windowID) }
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
                group.addTask { await Self.capture(window, maxSize: maxSize).map { (Int(window.windowID), $0) } }
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
        // `maxSize` is in pixels, not points: a tile is a few hundred pixels wide even when
        // a filter has left three of them, and a 2x bitmap was resampled down eightfold on
        // every frame while holding four times the memory.
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
