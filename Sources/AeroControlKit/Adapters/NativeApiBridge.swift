import AppKit

/// What AeroControl asks of macOS itself. A bridge that cannot capture leaves every tile a plate.
@MainActor
public protocol NativeApiBridge: Sendable {
    /// The app's icon, for the badge in a picture's corner.
    func appIcon(bundleId: String) -> NSImage
    /// Bundle ids of the apps macOS has hidden (⌘H): their windows are on no screen, and
    /// their tiles say so.
    func hiddenBundleIds() -> Set<String>

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
