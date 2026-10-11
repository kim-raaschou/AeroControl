import AppKit

@MainActor
protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage
    func liveWindow(_ id: Int, pixels: CGSize) -> NSView

    var canCapturePreviews: Bool { get }
    func requestPreviewAccess()
    func prepareCapture()
    func windowFrames(windowIds: [Int]) async -> [Int: CGRect]
    func windowPreviews(_ ids: [Int], filling sizes: [Int: CGSize], deliver: @MainActor (Int, CGImage) -> Void) async
}
