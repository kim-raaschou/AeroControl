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
}
