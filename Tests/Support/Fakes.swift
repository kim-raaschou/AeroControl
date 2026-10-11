import AppKit
import Testing
@testable import AeroControlKit
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
    func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async {
        captured.append(windowIds)
        for (n, id) in windowIds.enumerated() {
            if n == holdAfter { await withCheckedContinuation { held = $0 } }
            guard !blank.contains(id), !Task.isCancelled else { continue }       // a cancelled capture gives nothing, as ScreenCaptureKit's
            // In the window's shape, as large as fits — like a real capture.
            let shape = sizes[id] ?? CGSize(width: 300, height: 200)
            let scale = min(maxSize.width / shape.width, maxSize.height / shape.height)
            deliver(id, NSImage(size: CGSize(width: shape.width * scale, height: shape.height * scale)))
        }
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
