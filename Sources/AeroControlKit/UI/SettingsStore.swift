import Foundation

@MainActor @Observable
public final class SettingsStore {
    public private(set) var theme: AeroControlTheme

    private let defaults: UserDefaults
    private let themeKey = "settings.theme"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: themeKey).flatMap(AeroControlTheme.init(rawValue:)) ?? .system
    }

    public func setTheme(_ value: AeroControlTheme) {
        guard theme != value else { return }
        theme = value
        defaults.set(value.rawValue, forKey: themeKey)
    }

    public func reset() {
        setTheme(.system)
        // Keys written by versions before the one-shot overview.
        for key in ["settings.displayConfigs", "settings.iconSize", "settings.edge",
                    "settings.orientation", "settings.activeDisplay", "settings.multiScreenEnabled"] {
            defaults.removeObject(forKey: key)
        }
    }
}
