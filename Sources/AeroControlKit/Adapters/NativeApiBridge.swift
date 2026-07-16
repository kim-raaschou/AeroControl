import AppKit

/// The native macOS APIs that aerospace doesn't provide — icons and terminations.
@MainActor
public protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage
    func appTerminations() -> AsyncStream<Void>
    /// A permission-free doorbell for window closes that AeroSpace can't report:
    /// each left-mouse-up anywhere is a chance a background window was closed with
    /// the mouse, so it triggers a reconcile. Mirrors what AeroSpace does internally.
    func windowCloseSignals() -> AsyncStream<Void>
}
