import AppKit

@MainActor
protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage
    func liveWindow(_ id: Int, pixels: CGSize) -> NSView

    var canCapturePreviews: Bool { get }
    @discardableResult func requestPreviewAccess() -> Bool
    func prepareCapture()
    func windowFrames(windowIds: [Int]) -> [Int: CGRect]
    func windowPreviews(_ ids: [Int], filling sizes: [Int: CGSize], frames: [Int: CGRect], deliver: @MainActor (Int, CGImage) -> Void) async
}
