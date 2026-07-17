import AppKit
import Common

public final class NativeApiBridgeAdapter: NativeApiBridge {
    private var iconCache: [String: NSImage] = [:]
    private var closeMonitor: Any?

    public init() {}

    public func appIcon(bundleId: String) -> NSImage {
        if let cached = iconCache[bundleId] {
            return cached
        }
        let icon = Self.loadIcon(bundleId: bundleId)
        iconCache[bundleId] = icon
        return icon
    }

    public func appTerminations() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let terminations = NSWorkspace.shared.notificationCenter
                    .notifications(named: NSWorkspace.didTerminateApplicationNotification)
                for await _ in terminations {
                    continuation.yield()
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func windowCloseSignals() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.closeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
                continuation.yield()
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in self?.removeCloseMonitor() }
            }
        }
    }

    private func removeCloseMonitor() {
        if let closeMonitor { NSEvent.removeMonitor(closeMonitor) }
        closeMonitor = nil
    }

    private static func loadIcon(bundleId: String) -> NSImage {
        let original: NSImage
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            original = NSWorkspace.shared.icon(forFile: appURL.path)
        } else {
            original = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        return original
    }

}
