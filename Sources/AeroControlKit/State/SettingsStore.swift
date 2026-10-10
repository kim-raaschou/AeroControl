import Foundation

@MainActor @Observable
public final class SettingsStore {
    public var theme: AeroControlTheme { didSet { defaults.set(theme.id, forKey: themeKey) } }

    private let defaults: UserDefaults
    private let themeKey = "settings.theme"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: themeKey).flatMap(AeroControlTheme.named) ?? .system
    }
}
