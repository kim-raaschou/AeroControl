import AppKit

@MainActor
public protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage
    func liveWindow(_ id: Int, pixels: CGSize) -> NSView

    var canCapturePreviews: Bool { get }
    func requestPreviewAccess()
    func prepareCapture()
    func previewSizes(windowIds: [Int]) async -> [Int: CGSize]
    func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async
}
