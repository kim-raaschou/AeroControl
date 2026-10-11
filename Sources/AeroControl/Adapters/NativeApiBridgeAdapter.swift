import AppKit
import Common
import OSLog

@unsafe @preconcurrency import ScreenCaptureKit

private let log = Logger(subsystem: "com.aerocontrol.AeroControl", category: "previews")

final class NativeApiBridgeAdapter: NativeApiBridge {
    init() {}

    private var iconCache: [String: NSImage] = [:]

    func appIcon(bundleId: String) -> NSImage {
        if let cached = iconCache[bundleId] { return cached }
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId)
        let icon = Self.largeRepresentation(of: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle))
        iconCache[bundleId] = icon
        return icon
    }

    static func largeRepresentation(of image: NSImage) -> NSImage {
        let side: CGFloat = 256
        let rect = NSRect(x: 0, y: 0, width: side, height: side)
        guard let rep = image.bestRepresentation(for: rect, context: nil, hints: nil) else { return image }
        let large = NSImage(size: rect.size)
        large.addRepresentation(rep)
        return large
    }

    var canCapturePreviews: Bool { CGPreflightScreenCaptureAccess() }

    func requestPreviewAccess() {
        let granted = CGRequestScreenCaptureAccess()
        log.notice("previews: Screen Recording not granted; requested access -> \(granted)")
    }

    private var pendingContent: Task<SCShareableContent?, Never>?
    private var content: SCShareableContent?

    func prepareCapture() {
        guard canCapturePreviews else { return requestPreviewAccess() }
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

    func liveWindow(_ id: Int, pixels: CGSize) -> NSView {
        let view = LiveWindowView()
        Task { unsafe await resolvedContent()?.windows.first { unsafe Int($0.windowID) == id }.map { view.start($0, pixels: pixels) } }
        return view
    }

    func windowFrames(windowIds: [Int]) async -> [Int: CGRect] {
        guard canCapturePreviews else { return [:] }
        let wanted = Set(windowIds)
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.reduce(into: [:]) { frames, window in
            guard let id = window[kCGWindowNumber as String] as? Int, wanted.contains(id),
                  let bounds = window[kCGWindowBounds as String] as? [String: Double],
                  let width = bounds["Width"], let height = bounds["Height"], width > 1, height > 1 else { return }
            frames[id] = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: width, height: height)
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

    private static let parallelCaptures = 16

    func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async {
        guard canCapturePreviews else { log.notice("previews: Screen Recording not granted"); return }
        guard !windowIds.isEmpty, var content = await resolvedContent() else { return }
        let frames = await windowFrames(windowIds: windowIds)
        if content.windows.contains(where: { frames[Int($0.windowID)]?.size ?? $0.frame.size != $0.frame.size }),
           let fresh = await Self.shareableContent() {
            self.content = fresh
            content = fresh
        }
        let byId = Dictionary(content.windows.map { (Int($0.windowID), $0) }) { first, _ in first }
        let windows = windowIds.compactMap { byId[$0] }
        let started = ContinuousClock.now
        let captured = await withTaskGroup(of: (Int, NSImage)?.self, returning: Int.self) { group in
            var captured = 0
            @MainActor func land(_ landed: (Int, NSImage)?) { if let (id, image) = landed { deliver(id, image); captured += 1 } }
            for (index, window) in windows.enumerated() {
                if index >= Self.parallelCaptures, let landed = await group.next() { land(landed) }
                nonisolated(unsafe) let window = window
                let id = unsafe Int(window.windowID)
                group.addTask { unsafe await Self.capture(window, maxSize: maxSize).map { (id, $0) } }
            }
            for await landed in group { land(landed) }
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

@unsafe @preconcurrency import ScreenCaptureKit

final class LiveWindowView: NSView, SCStreamOutput {
    private nonisolated(unsafe) var stream: SCStream?
    private nonisolated(unsafe) var stopped = false
    private static let frameInterval = CMTime(value: 1, timescale: 20)

    func start(_ window: SCWindow, pixels: CGSize) {
        guard !stopped else { return }
        wantsLayer = true
        layer?.contentsGravity = .resizeAspectFill
        let config = SCStreamConfiguration()
        (config.width, config.height) = (max(1, Int(pixels.width)), max(1, Int(pixels.height)))
        config.minimumFrameInterval = Self.frameInterval
        config.showsCursor = false
        let stream = unsafe SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
        try? stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        self.stream = stream
        Task { try? await stream.startCapture() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    nonisolated func stop() {
        stopped = true
        _ = stream.map { stream in Task { try? await stream.stopCapture() } }
        stream = nil
    }

    deinit { stop() }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard let pixels = CMSampleBufferGetImageBuffer(buffer), let surface = CVPixelBufferGetIOSurface(pixels) else { return }
        nonisolated(unsafe) let frame = surface.takeUnretainedValue()
        MainActor.assumeIsolated { layer?.contents = frame }
    }
}
