import AppKit
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
