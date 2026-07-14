import AppKit
import ApplicationServices

/// A macOS privacy (TCC) permission AeroControl may require.
enum Permission: CaseIterable {
    /// Required to focus and move windows across workspaces via AeroSpace.
    case accessibility

    var isGranted: Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        }
    }

    /// Triggers the system prompt for this permission when it is missing.
    func requestPrompt() {
        switch self {
        case .accessibility:
            // kAXTrustedCheckOptionPrompt is an imported mutable C global, which
            // isn't concurrency-safe to read under Swift 6. Use its stable string
            // key directly (the Accessibility constant's documented value).
            let options = ["AXTrustedCheckOptionPrompt" as CFString: true]
            _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
    }
}

enum Permissions {
    /// Checks every required permission at startup and prompts for any that are
    /// missing. Non-blocking: the app still runs, though features relying on a
    /// missing permission degrade (e.g. focusing or moving windows).
    /// - Returns: true if all required permissions are granted.
    @discardableResult
    static func verifyAtStartup() -> Bool {
        var allGranted = true
        for permission in Permission.allCases {
            if !permission.isGranted {
                allGranted = false
                permission.requestPrompt()
            }
        }
        return allGranted
    }
}
