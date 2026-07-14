import CoreGraphics
import Foundation

/// Runtime, user-adjustable settings for the floating overview (icon size + position),
/// backed by `UserDefaults` and edited from the menu-bar (status item) menu — the app's
/// only configuration path; there are no launch flags.
///
/// `@Observable`, so SwiftUI views that read `iconSize` / `orientation` reflow
/// automatically. `orientation` is *derived* from `edge` (the single Position control).
@MainActor @Observable
public final class SettingsStore {
    /// The preferred app-icon size in points. Reading this in a SwiftUI body tracks
    /// it, so the panel reflows the moment it changes.
    public private(set) var iconSize: CGFloat
    /// The screen edge the widget docks to. The single placement control — its
    /// `orientation` is derived, not chosen separately.
    public private(set) var edge: DockEdge

    /// The layout axis, derived from the dock `edge` (top/bottom/center → horizontal,
    /// left/right → vertical). Reading it in a SwiftUI body tracks `edge`, so the panel
    /// reflows when the edge flips axis.
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

    private let defaults: UserDefaults
    private let iconSizeKey = "settings.iconSize"
    private let edgeKey = "settings.edge"
    /// Legacy key from when only an axis (not an edge) was persisted; read once to
    /// migrate an existing install to an equivalent edge.
    private let legacyOrientationKey = "settings.orientation"

    /// Seeds from persistence, falling back to the built-in defaults when nothing is
    /// saved yet (48 pt, top edge).
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let saved = defaults.object(forKey: iconSizeKey) as? Double {
            self.iconSize = Self.clamp(CGFloat(saved))
        } else {
            self.iconSize = AeroControlMetrics.defaultIconSize
        }
        if let raw = defaults.string(forKey: edgeKey), let e = DockEdge(rawValue: raw) {
            self.edge = e
        } else if let raw = defaults.string(forKey: legacyOrientationKey),
                  let o = Orientation(rawValue: raw) {
            // Migrate a pre-edge install to the matching edge, then persist so this
            // runs only once.
            self.edge = o.isVertical ? .left : .top
            defaults.set(edge.rawValue, forKey: edgeKey)
            defaults.removeObject(forKey: legacyOrientationKey)
        } else {
            self.edge = .top
        }
    }

    /// Sets and persists the icon size (clamped). No-op if unchanged.
    public func setIconSize(_ value: CGFloat) {
        let clamped = Self.clamp(value)
        guard clamped != iconSize else { return }
        iconSize = clamped
        defaults.set(Double(clamped), forKey: iconSizeKey)
    }

    /// Sets and persists the dock edge (and thus the derived orientation). No-op if
    /// unchanged.
    public func setEdge(_ value: DockEdge) {
        guard value != edge else { return }
        edge = value
        defaults.set(value.rawValue, forKey: edgeKey)
    }

    /// Forgets both saved settings and reverts to the built-in defaults (used by the
    /// menu's "Reset settings").
    public func reset() {
        defaults.removeObject(forKey: iconSizeKey)
        defaults.removeObject(forKey: edgeKey)
        defaults.removeObject(forKey: legacyOrientationKey)
        setIconSize(AeroControlMetrics.defaultIconSize)
        setEdge(.top)
    }

    private static func clamp(_ value: CGFloat) -> CGFloat {
        let sane = AeroControlMetrics.sanitizedIconSize(value)
        return min(maxPreferredIconSize, max(minPreferredIconSize, sane))
    }
}
