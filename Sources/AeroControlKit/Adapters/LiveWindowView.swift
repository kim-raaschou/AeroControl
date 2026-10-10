import AppKit
// ScreenCaptureKit's types are not marked Sendable yet; they are only ever touched on the main actor here.
@unsafe @preconcurrency import ScreenCaptureKit

/// A window's picture as it changes: one window streamed by ScreenCaptureKit, each frame put in
/// the layer as it comes, never through SwiftUI, so nothing else is drawn again for it. The
/// overview streams the window wearing the ring, one at a time, for as long as it wears it;
/// until the first frame the picture taken at the summon shows through.
final class LiveWindowView: NSView, SCStreamOutput {
    private nonisolated(unsafe) var stream: SCStream?
    /// About as often as a window changes in a glance; the window server sends no more.
    private static let frameInterval = CMTime(value: 1, timescale: 20)

    /// Streams `window` at `pixels`, the size it is drawn at, into the layer until `stop`.
    func start(_ window: SCWindow, pixels: CGSize) {
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        let config = SCStreamConfiguration()
        (config.width, config.height) = (max(1, Int(pixels.width)), max(1, Int(pixels.height)))
        config.minimumFrameInterval = Self.frameInterval
        config.showsCursor = false
        let stream = unsafe SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, delegate: nil)
        try? stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        self.stream = stream
        Task { try? await stream.startCapture() }
    }

    /// Stopped as the view leaves its window — the tile went, or the overview's window let its
    /// views go — and again when the view does: a stream left running is one the window server
    /// keeps counting, and one that holds this view as its output.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stop() }
    }

    nonisolated func stop() {
        _ = stream.map { stream in Task { try? await stream.stopCapture() } }
        stream = nil
    }

    deinit { stop() }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // A frame with nothing new has no image; the one before stays.
        guard let pixels = CMSampleBufferGetImageBuffer(buffer), let surface = CVPixelBufferGetIOSurface(pixels) else { return }
        nonisolated(unsafe) let frame = surface.takeUnretainedValue()
        MainActor.assumeIsolated { layer?.contents = frame }
    }
}
