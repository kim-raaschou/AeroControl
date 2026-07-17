import AppKit

@MainActor
public protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage
    func appTerminations() -> AsyncStream<Void>
    func windowCloseSignals() -> AsyncStream<Void>
}
