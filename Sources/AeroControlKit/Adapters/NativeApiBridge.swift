import AppKit

@MainActor
public protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage

    /// Whether window previews can be captured (macOS Screen Recording permission).
    var canCapturePreviews: Bool { get }
    /// Asks macOS for Screen Recording access; the system shows its own prompt/settings.
    func requestPreviewAccess()
    /// Starts whatever a capture needs that does not depend on which windows: called before
    /// AeroSpace is read, so the two overlap.
    func prepareCapture()
    /// The on-screen size of each window, in points, before any picture is taken: the grid
    /// takes its shape from these, so it does not reflow as pictures land.
    func previewSizes(windowIds: [Int]) async -> [Int: CGSize]
    /// One preview per window, scaled to fit `maxSize` (pixels), handed over one by one as
    /// each lands. Windows that cannot be captured are simply never delivered.
    func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async
}

/// Previews are optional: a bridge without capture support behaves like the icon-only
/// overview (this is also what the test fakes get).
public extension NativeApiBridge {
    var canCapturePreviews: Bool { false }
    func requestPreviewAccess() {}
    func prepareCapture() {}
    func previewSizes(windowIds: [Int]) async -> [Int: CGSize] { [:] }
    func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async {}
}
