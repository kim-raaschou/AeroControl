import CoreGraphics
import Foundation

@MainActor @Observable
public final class SettingsStore {
    public private(set) var activeDisplayKey: String
    public private(set) var multiScreenEnabled: Bool

    private let defaults: UserDefaults
    private let activeDisplayKeyKey = "settings.activeDisplay"
    private let multiScreenKey = "settings.multiScreenEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.activeDisplayKey = defaults.string(forKey: activeDisplayKeyKey) ?? ""
        self.multiScreenEnabled = defaults.bool(forKey: multiScreenKey)
    }

    public func setActiveDisplay(key: String, isBuiltin: Bool) {
        activeDisplayKey = key
        defaults.set(key, forKey: activeDisplayKeyKey)
    }

    public func setMultiScreenEnabled(_ enabled: Bool) {
        guard multiScreenEnabled != enabled else { return }
        multiScreenEnabled = enabled
        defaults.set(enabled, forKey: multiScreenKey)
    }

    public func reset() {
        setMultiScreenEnabled(false)
        for key in ["settings.displayConfigs", "settings.iconSize", "settings.edge", "settings.orientation"] {
            defaults.removeObject(forKey: key)   // written by versions before the one-shot overview
        }
    }
}
