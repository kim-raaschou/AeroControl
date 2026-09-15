import AppKit

@MainActor
public protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage
    func appTerminations() -> AsyncStream<Void>
    func windowCloseSignals() -> AsyncStream<Void>

    /// Whether window previews can be captured (macOS Screen Recording permission).
    var canCapturePreviews: Bool { get }
    /// Asks macOS for Screen Recording access; the system shows its own prompt/settings.
    func requestPreviewAccess()
    /// One preview image per window id, scaled to fit `maxSize` (points). Windows that
    /// cannot be captured are simply absent from the result.
    func windowPreviews(windowIds: [Int], maxSize: CGSize) async -> [Int: NSImage]
    /// Current frames (global, top-left origin, points) of the given windows, but only for
    /// windows that actually lie on a display: AeroSpace hides a workspace by parking its
    /// windows in a display corner, and those must not count. Needs no permission.
    func windowFrames(windowIds: [Int]) -> [Int: CGRect]
}

/// Previews are optional: a bridge without capture support behaves like the icon-only
/// overview (this is also what the test fakes get).
public extension NativeApiBridge {
    var canCapturePreviews: Bool { false }
    func requestPreviewAccess() {}
    func windowPreviews(windowIds: [Int], maxSize: CGSize) async -> [Int: NSImage] { [:] }
    func windowFrames(windowIds: [Int]) -> [Int: CGRect] { [:] }
}
