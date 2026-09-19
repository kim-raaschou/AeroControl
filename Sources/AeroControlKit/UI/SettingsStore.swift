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
    public private(set) var theme: AeroControlTheme
    /// How much the backdrop dims what is behind the overview: 1 is the palette's own tint,
    /// less lets the desktop through.
    public private(set) var backdropOpacity: Double
    public private(set) var animationSpeed: AnimationSpeed

    /// Below ~70 % the desktop competes with the cards; the useful range is narrow, so the
    /// steps are small.
    public static let backdropOpacities: [Double] = [1, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7]

    private let defaults: UserDefaults
    private let themeKey = "settings.theme"
    private let backdropKey = "settings.backdropOpacity"
    private let animationKey = "settings.animationSpeed"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.theme = defaults.string(forKey: themeKey).flatMap(AeroControlTheme.named) ?? .system
        let opacity = defaults.object(forKey: backdropKey) as? Double
        self.backdropOpacity = opacity.map { min(max($0, 0), 1) } ?? 1
        self.animationSpeed = defaults.string(forKey: animationKey).flatMap(AnimationSpeed.init) ?? .normal
    }

    public func setTheme(_ value: AeroControlTheme) {
        guard theme != value else { return }
        theme = value
        defaults.set(value.id, forKey: themeKey)
    }

    public func setBackdropOpacity(_ value: Double) {
        backdropOpacity = min(max(value, 0), 1)
        defaults.set(backdropOpacity, forKey: backdropKey)
    }

    public func setAnimationSpeed(_ value: AnimationSpeed) {
        animationSpeed = value
        defaults.set(value.rawValue, forKey: animationKey)
    }

    public func reset() {
        setTheme(.system)
        setBackdropOpacity(1)
        setAnimationSpeed(.normal)
        // Keys written by versions before the one-shot overview.
        for key in ["settings.displayConfigs", "settings.iconSize", "settings.edge",
                    "settings.orientation", "settings.activeDisplay", "settings.multiScreenEnabled"] {
            defaults.removeObject(forKey: key)
        }
    }
}
