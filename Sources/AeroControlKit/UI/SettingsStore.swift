import CoreGraphics
import Foundation

/// The full per-screen configuration for the floating overview: where it docks
/// (`edge`) and its preferred app-icon size. Every physical display keeps its own,
/// so the built-in display can be a centered HUD while an external is a menu-bar
/// strip — with independent icon sizes. Codable so the whole map persists as JSON.
public struct DisplayConfig: Codable, Equatable, Sendable {
    /// The screen edge the widget docks to on this display. Its `orientation` is
    /// derived, not chosen separately.
    public var edge: DockEdge
    /// The preferred app-icon size (points) on this display.
    public var iconSize: CGFloat

    public init(edge: DockEdge, iconSize: CGFloat) {
        self.edge = edge
        self.iconSize = iconSize
    }
}

/// Runtime, user-adjustable settings for the floating overview, backed by
/// `UserDefaults` and edited from the menu-bar (status item) menu — the app's only
/// configuration path; there are no launch flags.
///
/// **Everything is per screen.** The store holds a `DisplayConfig` (edge + icon size)
/// for each physical display, keyed by a persistence-stable display id, plus which
/// display is currently *active* (the one the widget is shown on). The public
/// `edge` / `iconSize` / `orientation` / `effectiveIconSize` accessors read the
/// *active* display's config, and `setEdge` / `setIconSize` write it — so the menu
/// and the SwiftUI panel keep working against the same surface while every value is
/// scoped to the selected screen.
///
/// `@Observable`, so SwiftUI views that read `iconSize` / `orientation` reflow
/// automatically when the active config (or the active display) changes.
@MainActor @Observable
public final class SettingsStore {
    /// The key of the display the widget is currently shown on. `setActiveDisplay`
    /// updates it (from the Screen menu); the accessors below resolve their values
    /// from this display's config.
    public private(set) var activeDisplayKey: String
    /// Whether the active display is the built-in one, so a display with no saved
    /// config yet defaults sensibly (built-in → centered HUD, external → menu bar).
    private var activeIsBuiltin: Bool
    /// Per-display configs, keyed by the stable display id. Absent keys fall back to
    /// the built-in/external default lazily, so nothing is written until the user
    /// actually customizes a screen.
    private var configs: [String: DisplayConfig]
    /// Legacy pre-per-screen global settings, captured once at init so the user's
    /// existing edge/icon size migrate onto the first screen they select rather than
    /// being lost. Cleared after the first `setActiveDisplay` seeds a config.
    private var pendingMigration: DisplayConfig?

    /// The active display's config, or its lazy per-type default when unset.
    private var activeConfig: DisplayConfig {
        configs[activeDisplayKey] ?? Self.defaultConfig(isBuiltin: activeIsBuiltin)
    }

    /// The active display's dock edge. Reading it in a SwiftUI body tracks the active
    /// config, so the panel reflows when the edge (or the active display) changes.
    public var edge: DockEdge { activeConfig.edge }
    /// The active display's preferred app-icon size.
    public var iconSize: CGFloat { activeConfig.iconSize }
    /// The layout axis, derived from the active display's dock `edge`.
    public var orientation: Orientation { edge.orientation }

    /// The selectable icon-size presets surfaced in the menu, small→large. Kept
    /// inside `[minPreferredIconSize, maxPreferredIconSize]`; `48` is the default. The
    /// smallest fits a compact, menu-bar-style overlay; `96` is a roomy, glanceable HUD.
    public static let iconSizePresets: [CGFloat] = [16, 24, 32, 48, 96]

    /// Sanity bounds for the preferred icon size. The max keeps a single busy
    /// workspace from producing an absurdly large widget; the min keeps labels
    /// legible. Adaptive shrinking below the min is still allowed at render time so
    /// content never clips.
    public static let minPreferredIconSize: CGFloat = 16
    public static let maxPreferredIconSize: CGFloat = 96

    /// The fixed icon size used by the `menuBar` dock position, chosen to match the
    /// native macOS menu-bar icon size so the strip reads as part of the menu bar.
    /// Overrides the display's `iconSize` while that position is selected.
    public static let menuBarIconSize: CGFloat = 18

    /// The icon size the overview should actually render at: the native menu-bar size
    /// when the active display is docked to the menu bar, otherwise its chosen preset.
    public var effectiveIconSize: CGFloat {
        edge.isMenuBar ? Self.menuBarIconSize : iconSize
    }

    private let defaults: UserDefaults
    private let configsKey = "settings.displayConfigs"
    private let activeDisplayKeyKey = "settings.activeDisplay"
    /// Legacy keys from the pre-per-screen (single global edge/icon size) install,
    /// read once to migrate an existing setup onto the first selected screen.
    private let legacyIconSizeKey = "settings.iconSize"
    private let legacyEdgeKey = "settings.edge"
    private let legacyOrientationKey = "settings.orientation"

    /// Seeds from persistence. Per-screen configs and the active display are restored;
    /// a legacy single-edge install is captured for one-time migration onto the first
    /// screen the widget lands on.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.configs = Self.loadConfigs(from: defaults, key: configsKey)
        self.activeDisplayKey = defaults.string(forKey: activeDisplayKeyKey) ?? ""
        self.activeIsBuiltin = true
        // Capture a legacy global install so its edge/icon size migrate onto the first
        // selected screen instead of vanishing. Only when no per-screen config exists.
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

    /// Switches the active display (from the Screen menu). Seeds the display's config
    /// on first selection — migrating a legacy global install if one was captured,
    /// otherwise the built-in/external default — and persists the active key.
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

    /// Sets and persists the active display's icon size (clamped). No-op if unchanged.
    public func setIconSize(_ value: CGFloat) {
        let clamped = Self.clamp(value)
        var config = activeConfig
        guard config.iconSize != clamped else { return }
        config.iconSize = clamped
        configs[activeDisplayKey] = config
        persistConfigs()
    }

    /// Sets and persists the active display's dock edge (and thus its derived
    /// orientation). No-op if unchanged.
    public func setEdge(_ value: DockEdge) {
        var config = activeConfig
        guard config.edge != value else { return }
        config.edge = value
        configs[activeDisplayKey] = config
        persistConfigs()
    }

    /// Forgets every per-screen config (and any captured legacy settings), so each
    /// display reverts to its built-in/external default. The active display selection
    /// is kept.
    public func reset() {
        configs.removeAll()
        pendingMigration = nil
        defaults.removeObject(forKey: configsKey)
        defaults.removeObject(forKey: legacyEdgeKey)
        defaults.removeObject(forKey: legacyIconSizeKey)
        defaults.removeObject(forKey: legacyOrientationKey)
    }

    /// The lazy default config for a display with nothing saved yet: a centered HUD on
    /// the built-in display, a menu-bar strip on externals; default icon size.
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
