import AppKit

@MainActor
public protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage
    func liveWindow(_ id: Int, pixels: CGSize) -> NSView

    var canCapturePreviews: Bool { get }
    func requestPreviewAccess()
    func prepareCapture()
    func windowFrames(windowIds: [Int]) async -> [Int: CGRect]
    func windowPreviews(windowIds: [Int], maxSize: CGSize, deliver: @MainActor (Int, NSImage) -> Void) async
}
