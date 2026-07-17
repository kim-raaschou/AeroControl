import CoreGraphics
import Foundation

public struct DisplayConfig: Codable, Equatable, Sendable {
    public var edge: DockEdge
    public var iconSize: CGFloat

    public init(edge: DockEdge, iconSize: CGFloat) {
        self.edge = edge
        self.iconSize = iconSize
    }
}

@MainActor @Observable
public final class SettingsStore {
    public private(set) var activeDisplayKey: String
    private var activeIsBuiltin: Bool
    private var configs: [String: DisplayConfig]
    private var pendingMigration: DisplayConfig?

    public private(set) var multiScreenEnabled: Bool

    private var activeConfig: DisplayConfig {
        configs[activeDisplayKey] ?? Self.defaultConfig(isBuiltin: activeIsBuiltin)
    }

    public func config(forKey key: String, isBuiltin: Bool) -> DisplayConfig {
        configs[key] ?? Self.defaultConfig(isBuiltin: isBuiltin)
    }

    public var edge: DockEdge { activeConfig.edge }
    public var iconSize: CGFloat { activeConfig.iconSize }
    public var orientation: Orientation { edge.orientation }

    public static let iconSizePresets: [CGFloat] = [16, 24, 32, 48, 96]

    public static let minPreferredIconSize: CGFloat = 16
    public static let maxPreferredIconSize: CGFloat = 96

    public var effectiveIconSize: CGFloat { iconSize }

    private let defaults: UserDefaults
    private let configsKey = "settings.displayConfigs"
    private let activeDisplayKeyKey = "settings.activeDisplay"
    private let multiScreenKey = "settings.multiScreenEnabled"
    private let legacyIconSizeKey = "settings.iconSize"
    private let legacyEdgeKey = "settings.edge"
    private let legacyOrientationKey = "settings.orientation"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.configs = Self.loadConfigs(from: defaults, key: configsKey)
        self.activeDisplayKey = defaults.string(forKey: activeDisplayKeyKey) ?? ""
        self.activeIsBuiltin = true
        self.multiScreenEnabled = defaults.bool(forKey: multiScreenKey)
        if configs.isEmpty {
            if let raw = defaults.string(forKey: legacyEdgeKey), let e = DockEdge(rawValue: raw) {
                let saved = (defaults.object(forKey: legacyIconSizeKey) as? Double).map { CGFloat($0) }
                pendingMigration = DisplayConfig(edge: e, iconSize: Self.clamp(saved ?? AeroControlMetrics.defaultIconSize))
            } else if let raw = defaults.string(forKey: legacyOrientationKey),
                      let o = Orientation(rawValue: raw) {
                pendingMigration = DisplayConfig(edge: o.isVertical ? .left : .top, iconSize: AeroControlMetrics.defaultIconSize)
            }
        }
    }

    public func setActiveDisplay(key: String, isBuiltin: Bool) {
        activeIsBuiltin = isBuiltin
        activeDisplayKey = key
        defaults.set(key, forKey: activeDisplayKeyKey)
        if configs[key] == nil, let migrated = pendingMigration {
            configs[key] = migrated
            pendingMigration = nil
            persistConfigs()
            defaults.removeObject(forKey: legacyEdgeKey)
            defaults.removeObject(forKey: legacyIconSizeKey)
            defaults.removeObject(forKey: legacyOrientationKey)
        }
    }

    public func setMultiScreenEnabled(_ enabled: Bool) {
        guard multiScreenEnabled != enabled else { return }
        multiScreenEnabled = enabled
        defaults.set(enabled, forKey: multiScreenKey)
    }

    public func setIconSize(_ value: CGFloat) {
        let clamped = Self.clamp(value)
        var config = activeConfig
        guard config.iconSize != clamped else { return }
        config.iconSize = clamped
        configs[activeDisplayKey] = config
        persistConfigs()
    }

    public func setEdge(_ value: DockEdge) {
        var config = activeConfig
        guard config.edge != value else { return }
        config.edge = value
        configs[activeDisplayKey] = config
        persistConfigs()
    }

    public func reset() {
        configs.removeAll()
        pendingMigration = nil
        defaults.removeObject(forKey: configsKey)
        defaults.removeObject(forKey: legacyEdgeKey)
        defaults.removeObject(forKey: legacyIconSizeKey)
        defaults.removeObject(forKey: legacyOrientationKey)
    }

    static func defaultConfig(isBuiltin: Bool) -> DisplayConfig {
        DisplayConfig(
            edge: isBuiltin ? .center : .menuBar,
            iconSize: AeroControlMetrics.defaultIconSize
        )
    }

    private func persistConfigs() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        defaults.set(data, forKey: configsKey)
    }

    private static func loadConfigs(from defaults: UserDefaults, key: String) -> [String: DisplayConfig] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: DisplayConfig].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        let sane = AeroControlMetrics.sanitizedIconSize(value)
        return min(maxPreferredIconSize, max(minPreferredIconSize, sane))
    }
}
