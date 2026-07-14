import AppKit

/// The native macOS APIs that aerospace doesn't provide — liveness, icons, terminations.
@MainActor
public protocol NativeApiBridge: Sendable {
    func liveWindowIds() -> Set<Int>
    func appIcon(bundleId: String) -> NSImage
    func appTerminations() -> AsyncStream<Void>
}
