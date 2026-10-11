import AppKit
import Testing
@testable import AeroControl
@testable import Common

/// Native bridge a test can drive: icons and preview capture.
@MainActor
final class FakeBridge: NativeApiBridge {
    /// Screen Recording granted?
    var granted = false
    /// Every window-id list the store has asked to capture.
    var captured: [[Int]] = []
    /// What the bridge gives for any app's icon, and for a live picture: one each, to be recognised.
    let icon = NSImage()
    let live = NSView()
    func appIcon(bundleId: String) -> NSImage { icon }
    func liveWindow(_ id: Int, pixels: CGSize) -> NSView { live }
    var canCapturePreviews: Bool { granted }
    func requestPreviewAccess() {}
    func prepareCapture() {}
    /// What the window server reports per window; 300 × 200 for any not listed.
    var sizes: [Int: CGSize] = [:]
    /// How many times sizes were read.
    var measured = 0
    func windowFrames(windowIds: [Int]) async -> [Int: CGRect] {
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
    func windowPreviews(_ ids: [Int], filling boxes: [Int: CGSize], deliver: @MainActor (Int, CGImage) -> Void) async {
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

@MainActor
func waitUntil(_ cond: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
    let deadline = ContinuousClock.now + .seconds(2)
    while ContinuousClock.now < deadline {
        if cond() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("waited 2 s and the condition never held", sourceLocation: sourceLocation)
}

/// Counts how many times the store's `@Observable` `model` invalidates — i.e. how many
/// times SwiftUI's `NSHostingView` would re-render. Re-registers after each change.
@MainActor
final class ModelInvalidationCounter {
    private(set) var count = 0
    private let store: OverviewStore

    init(_ store: OverviewStore) {
        self.store = store
        register()
    }

    private func register() {
        withObservationTracking {
            _ = store.visit.model
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.count += 1
                self?.register()
            }
        }
    }
}
