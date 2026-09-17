import AppKit

@MainActor
public protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage

    /// Whether window previews can be captured (macOS Screen Recording permission).
    var canCapturePreviews: Bool { get }
    /// Asks macOS for Screen Recording access; the system shows its own prompt/settings.
    func requestPreviewAccess()
    /// One preview image per window id, scaled to fit `maxSize` (points). Windows that
    /// cannot be captured are simply absent from the result.
    func windowPreviews(windowIds: [Int], maxSize: CGSize) async -> [Int: NSImage]
}

/// Previews are optional: a bridge without capture support behaves like the icon-only
/// overview (this is also what the test fakes get).
public extension NativeApiBridge {
    var canCapturePreviews: Bool { false }
    func requestPreviewAccess() {}
    func windowPreviews(windowIds: [Int], maxSize: CGSize) async -> [Int: NSImage] { [:] }
}
