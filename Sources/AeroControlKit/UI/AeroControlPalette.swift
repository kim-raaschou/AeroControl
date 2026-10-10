import Common
import SwiftUI

/// Every color the overview draws.
public struct AeroControlPalette: Sendable {
    public let accent: Color
    public let cardFill: Color?
    public let cardBorder: Color
    public let badgeFill: Color
    public let badgeText: Color
    public let focusedBadgeText: Color
    public let closeButtonFill: Color
    public let backdrop: Color

    /// The palette a theme draws with in `scheme`: its own fixed one, or the platform's.
    public static func of(_ theme: AeroControlTheme, in scheme: ColorScheme) -> AeroControlPalette {
        theme.base.map(derived(from:)) ?? system(scheme)
    }

    /// A factory rather than an `init`, so the struct keeps its synthesized memberwise initializer
    /// and `system(_:)` below needs no hand-written one.
    static func derived(from base: BasePalette) -> AeroControlPalette {
        AeroControlPalette(
            accent: Color(hex: base.accent),
            cardFill: Color(hex: base.background).opacity(0.78),
            cardBorder: Color(hex: base.border),
            badgeFill: Color(hex: base.surface),
            badgeText: Color(hex: base.muted),
            focusedBadgeText: Color(hex: base.background),
            closeButtonFill: Color(hex: base.border),
            // The palette's own background, translucent enough for the blur to read through.
            backdrop: Color(hex: base.background).opacity(base.isDark ? 0.62 : 0.5)
        )
    }

    static func system(_ scheme: ColorScheme) -> AeroControlPalette {
        let dark = scheme == .dark
        return AeroControlPalette(
            accent: .accentColor,
            cardFill: nil,
            cardBorder: dark ? .white.opacity(0.18) : .black.opacity(0.12),
            badgeFill: dark ? .white.opacity(0.10) : .black.opacity(0.07),
            badgeText: .secondary,
            focusedBadgeText: .white,
            closeButtonFill: Color(white: dark ? 0.26 : 0.92),
            backdrop: .black.opacity(0.35)
        )
    }

}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// What every overview view draws with, resolved once at the root: the palette for the theme and
/// the window's appearance, and the animation scale from settings, by which every duration is
/// multiplied, so 0 is instant and 2 is leisurely; and, set by the panel, where it is drawn.
public struct AeroLook: Sendable {
    public let palette: AeroControlPalette
    public let motion: Double
    public let surface: AeroSurface
    public init(palette: AeroControlPalette, motion: Double, surface: AeroSurface = .map) { (self.palette, self.motion, self.surface) = (palette, motion, surface) }
}

/// Where a card or a tile is drawn: on the map, where a tile is dragged and closed and a card lies
/// on the dimmed desktop; or in the strip, which only chooses, over the bare desktop.
public enum AeroSurface: Sendable { case map, strip }

private struct AeroLookKey: EnvironmentKey {
    static let defaultValue = AeroLook(palette: AeroControlPalette.of(.system, in: .dark), motion: 1)
}

public extension EnvironmentValues {
    var aeroLook: AeroLook {
        get { self[AeroLookKey.self] }
        set { self[AeroLookKey.self] = newValue }
    }
}
