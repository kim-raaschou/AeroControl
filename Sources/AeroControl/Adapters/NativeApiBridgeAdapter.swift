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
        let icon = Self.icon(at: NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId))
        iconCache[bundleId] = icon
        return icon
    }

    static func icon(at url: URL?) -> NSImage { url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle) }

    var canCapturePreviews: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult func requestPreviewAccess() -> Bool {
        let granted = CGRequestScreenCaptureAccess()
        log.notice("previews: Screen Recording not granted; requested access -> \(granted)")
        return granted
    }

    private var pendingContent: Task<SCShareableContent?, Never>?
    private var content: SCShareableContent?

    func prepareCapture() {
        guard canCapturePreviews else { requestPreviewAccess(); return }
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

    func windowFrames(windowIds: [Int]) -> [Int: CGRect] {
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

    func windowPreviews(_ ids: [Int], filling sizes: [Int: CGSize], deliver: @MainActor (Int, CGImage) -> Void) async {
        guard canCapturePreviews else { log.notice("previews: Screen Recording not granted"); return }
        guard !ids.isEmpty, var content = await resolvedContent() else { return }
        if !Set(ids).isSubset(of: content.windows.map { Int($0.windowID) }), let fresh = await Self.shareableContent() { (self.content, content) = (fresh, fresh) }
        let frames = windowFrames(windowIds: ids)
        let byId = Dictionary(content.windows.map { (Int($0.windowID), $0) }) { first, _ in first }
        let windows = ids.compactMap { id in byId[id].flatMap { window in sizes[id].map { (window, frames[id]?.size ?? window.frame.size, $0) } } }
        let started = ContinuousClock.now
        let captured = await withTaskGroup(of: (Int, CGImage)?.self, returning: Int.self) { group in
            var captured = 0
            @MainActor func land(_ landed: (Int, CGImage)?) { if let (id, image) = landed { deliver(id, image); captured += 1 } }
            for (index, (window, frame, size)) in windows.enumerated() {
                if index >= Self.parallelCaptures, let landed = await group.next() { land(landed) }
                nonisolated(unsafe) let window = window
                let id = unsafe Int(window.windowID)
                group.addTask { unsafe await Self.capture(window, sized: frame, filling: size).map { (id, $0) } }
            }
            for await landed in group { land(landed) }
            return captured
        }
        let ms = (ContinuousClock.now - started) / .milliseconds(1)
        log.notice("previews: requested \(ids.count) captured \(captured) in \(Int(ms)) ms")
    }

    private static func capture(_ window: SCWindow, sized frame: CGSize, filling size: CGSize) async -> CGImage? {
        guard frame.width > 1, frame.height > 1 else { return nil }
        let scale = min(max(size.width / frame.width, size.height / frame.height), 1)
        let config = SCStreamConfiguration()
        config.width = max(1, Int((frame.width * scale).rounded()))
        config.height = max(1, Int((frame.height * scale).rounded()))
        config.showsCursor = false
        do {
            return try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        } catch {
            log.error("previews: capture of window \(window.windowID) failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
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
        config.scalesToFit = true
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
