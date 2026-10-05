import Foundation

@MainActor @Observable
public final class SettingsStore {
    public var theme: AeroControlTheme { didSet { defaults.set(theme.id, forKey: themeKey) } }
    /// Whether an app summon with windows to choose between shows the strip. Off, the key
    /// brings the app forward and macOS decides which of its windows is in front.
    public var appPicker: Bool { didSet { defaults.set(appPicker, forKey: appPickerKey) } }

    private let defaults: UserDefaults
    private let themeKey = "settings.theme"
    private let appPickerKey = "settings.appPickerEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: themeKey).flatMap(AeroControlTheme.named) ?? .system
        self.appPicker = defaults.object(forKey: appPickerKey) as? Bool ?? true
    }

    public func reset() {
        theme = .system
        appPicker = true
    }
}
