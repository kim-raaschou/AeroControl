import AppKit
import CoreGraphics

extension NSScreen {
    /// The physical display's `CGDirectDisplayID`, used to tell whether a focus change
    /// crossed to a different monitor (so a same-screen change is a cheap no-op). Falls
    /// back to 0 if the description is missing.
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    /// A persistence-stable identity for this physical display, used to key its
    /// per-screen configuration. Prefers the display's `CGDisplayCreateUUIDFromDisplayID`
    /// UUID (stable across reconnects/reboots, unlike the numeric `displayID`); falls
    /// back to the numeric id as a string when no UUID is available.
    var displayUUID: String {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return String(displayID)
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    /// True for the Mac's built-in display, so its per-screen config can default to a
    /// centered HUD while external displays default to the menu-bar strip.
    var isBuiltin: Bool {
        CGDisplayIsBuiltin(displayID) != 0
    }
}
