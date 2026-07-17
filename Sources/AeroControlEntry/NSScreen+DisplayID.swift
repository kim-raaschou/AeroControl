import AppKit
import CoreGraphics

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (deviceDescription[key] as? NSNumber)?.uint32Value ?? 0
    }

    var displayUUID: String {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return String(displayID)
        }
        return CFUUIDCreateString(nil, cfUUID) as String
    }

    var isBuiltin: Bool {
        CGDisplayIsBuiltin(displayID) != 0
    }
}
