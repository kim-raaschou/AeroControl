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
            // Global monitors for mouse events need no Accessibility permission (unlike
            // keyboard). We only reconcile — we never consume or inspect the event.
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
        // 100% native: return the raw macOS icon untouched, exactly as the Dock and
        // the Cmd-Tab switcher render it. SwiftUI sizes the multi-representation image
        // to the tile; no cropping or rescaling so we never diverge from the OS look.
        return original
    }

}
