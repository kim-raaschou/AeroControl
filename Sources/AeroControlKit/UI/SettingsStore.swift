import CoreGraphics
import Foundation

@MainActor @Observable
public final class SettingsStore {
    public private(set) var activeDisplayKey: String
    public private(set) var multiScreenEnabled: Bool
    public private(set) var theme: AeroControlTheme

    private let defaults: UserDefaults
    private let activeDisplayKeyKey = "settings.activeDisplay"
    private let multiScreenKey = "settings.multiScreenEnabled"
    private let themeKey = "settings.theme"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.activeDisplayKey = defaults.string(forKey: activeDisplayKeyKey) ?? ""
        self.multiScreenEnabled = defaults.bool(forKey: multiScreenKey)
        self.theme = defaults.string(forKey: themeKey).flatMap(AeroControlTheme.init(rawValue:)) ?? .system
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

    public func setTheme(_ value: AeroControlTheme) {
        guard theme != value else { return }
        theme = value
        defaults.set(value.rawValue, forKey: themeKey)
    }

    public func reset() {
        setMultiScreenEnabled(false)
        setTheme(.system)
        for key in ["settings.displayConfigs", "settings.iconSize", "settings.edge", "settings.orientation"] {
            defaults.removeObject(forKey: key)   // written by versions before the one-shot overview
        }
    }
}
