import AppKit

/// The native macOS APIs that aerospace doesn't provide — icons and terminations.
@MainActor
public protocol NativeApiBridge: Sendable {
    func appIcon(bundleId: String) -> NSImage
    func appTerminations() -> AsyncStream<Void>
}
