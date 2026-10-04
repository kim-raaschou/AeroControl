import Foundation

/// How fast the overview moves: the reveal, the grid reflow, a picture landing. One scale
/// on every duration, so the choice is a feel, not four numbers.
public enum AnimationSpeed: String, CaseIterable, Sendable {
    case off, fast, normal, slow

    public var scale: Double {
        switch self {
        case .off: 0
        case .fast: 0.5
        case .normal: 1
        case .slow: 2
        }
    }

    public var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

@MainActor @Observable
public final class SettingsStore {
    public var theme: AeroControlTheme { didSet { defaults.set(theme.id, forKey: themeKey) } }
    /// How much the backdrop dims what is behind the overview: 1 is the palette's own tint,
    /// less lets the desktop through.
    public var backdropOpacity: Double { didSet { defaults.set(backdropOpacity, forKey: backdropKey) } }
    public var animationSpeed: AnimationSpeed { didSet { defaults.set(animationSpeed.rawValue, forKey: animationKey) } }
    /// Whether an app summon with windows to choose between shows the strip. Off, the key
    /// brings the app forward and macOS decides which of its windows is in front.
    public var appPicker: Bool { didSet { defaults.set(appPicker, forKey: appPickerKey) } }

    /// Below ~70 % the desktop competes with the cards; the useful range is narrow, so the
    /// steps are small.
    public static let backdropOpacities: [Double] = [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7]

    private let defaults: UserDefaults
    private let themeKey = "settings.theme"
    private let backdropKey = "settings.backdropOpacity"
    private let animationKey = "settings.animationSpeed"
    private let appPickerKey = "settings.appPickerEnabled"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: themeKey).flatMap(AeroControlTheme.named) ?? .system
        let opacity = defaults.object(forKey: backdropKey) as? Double
        self.backdropOpacity = opacity.map { min(max($0, 0), 1) } ?? 1
        self.animationSpeed = defaults.string(forKey: animationKey).flatMap(AnimationSpeed.init) ?? .normal
        self.appPicker = defaults.object(forKey: appPickerKey) as? Bool ?? true
    }

    public func reset() {
        theme = .system
        backdropOpacity = 1
        animationSpeed = .normal
        appPicker = true
    }
}
