import AppKit
import Testing
@testable import AeroControl
@testable import Common

/// Native bridge a test can drive: icons and preview capture.
@MainActor
final class FakeBridge: NativeApiBridge {
    /// Every window-id list the store has asked to capture.
    var captured: [[Int]] = []
    func appIcon(bundleId: String) -> NSImage { NSImage() }
    func liveWindow(_ id: Int, pixels: CGSize) -> NSView { NSView() }
    var canCapturePreviews: Bool { true }
    func requestPreviewAccess() -> Bool { false }
    func prepareCapture() {}
    /// What the window server reports per window; 300 × 200 for any not listed.
    var sizes: [Int: CGSize] = [:]
    /// How many times sizes were read.
    var measured = 0
    func windowFrames(windowIds: [Int]) -> [Int: CGRect] {
        measured += 1
        return Dictionary(uniqueKeysWithValues: windowIds.map { ($0, CGRect(origin: .zero, size: sizes[$0] ?? CGSize(width: 300, height: 200))) })
    }
    /// Windows that give no picture, as one the window server cannot capture.
    var blank: Set<Int> = []
    /// When set, a capture delivers this many pictures and then waits for `release()`.
    var holdAfter: Int?
    private var held: CheckedContinuation<Void, Never>?
    var isHolding: Bool { held != nil }
    func release() { held?.resume(); held = nil }
    /// The pixels each window's picture was asked to fill, last time it was taken.
    var filling: [Int: CGSize] = [:]
    func windowPreviews(_ ids: [Int], filling boxes: [Int: CGSize], frames: [Int: CGRect], deliver: @MainActor (Int, CGImage) -> Void) async {
        captured.append(ids)
        for (n, id) in ids.enumerated() {
            if n == holdAfter { await withCheckedContinuation { held = $0 } }
            guard !blank.contains(id), !Task.isCancelled, let box = boxes[id] else { continue }   // a cancelled capture gives nothing, as ScreenCaptureKit's
            filling[id] = box
            // In the window's shape, just covering the box — like a real capture.
            let shape = sizes[id] ?? CGSize(width: 300, height: 200)
            let scale = max(box.width / shape.width, box.height / shape.height)
            deliver(id, picture(CGSize(width: shape.width * scale, height: shape.height * scale)))
        }
    }

    private func picture(_ size: CGSize) -> CGImage {
        CGContext(data: nil, width: max(1, Int(size.width.rounded())), height: max(1, Int(size.height.rounded())), bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!.makeImage()!
    }
}

final class Flag: @unchecked Sendable { var on = false }
