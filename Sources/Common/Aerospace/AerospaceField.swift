import Foundation

public enum AerospaceField: String, CaseIterable, CodingKey {
    case windowId = "window-id"
    case appName = "app-name"
    case appBundleId = "app-bundle-id"
    case workspace = "workspace"
    case parentLayout = "window-parent-container-layout"
    case monitorId = "monitor-id"
    case nsScreenId = "monitor-appkit-nsscreen-screens-id"

    public var formatToken: String { "%{\(rawValue)}" }
}

extension Array where Element == AerospaceField {
    public var formatString: String {
        map(\.formatToken).joined(separator: " ")
    }
}
