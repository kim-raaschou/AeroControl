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
    /// One preview image per window id, scaled to fit `maxSize` (pixels). Windows that
    /// cannot be captured are simply absent from the result.
    func windowPreviews(windowIds: [Int], maxSize: CGSize) async -> [Int: NSImage]
}

/// Previews are optional: a bridge without capture support behaves like the icon-only
/// overview (this is also what the test fakes get).
public extension NativeApiBridge {
    var canCapturePreviews: Bool { false }
    func requestPreviewAccess() {}
    func prepareCapture() {}
    func windowPreviews(windowIds: [Int], maxSize: CGSize) async -> [Int: NSImage] { [:] }
}
