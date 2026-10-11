import Common
import SwiftUI

struct AeroControlPalette: Sendable {
    let accent: Color
    let cardFill: Color?
    let cardBorder: Color
    let badgeFill: Color
    let badgeText: Color
    let focusedBadgeText: Color
    let closeButtonFill: Color
    let backdrop: Color

    static func of(_ theme: AeroControlTheme, in scheme: ColorScheme) -> AeroControlPalette {
        theme.base.map(derived(from:)) ?? system(scheme)
    }

    static func derived(from base: BasePalette) -> AeroControlPalette {
        AeroControlPalette(
            accent: Color(hex: base.accent),
            cardFill: Color(hex: base.background).opacity(0.78),
            cardBorder: Color(hex: base.border),
            badgeFill: Color(hex: base.surface),
            badgeText: Color(hex: base.muted),
            focusedBadgeText: Color(hex: base.background),
            closeButtonFill: Color(hex: base.border),
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

struct AeroLook: Sendable {
    let palette: AeroControlPalette
    let motion: Double
    let surface: AeroSurface
    init(palette: AeroControlPalette, motion: Double, surface: AeroSurface = .map) { (self.palette, self.motion, self.surface) = (palette, motion, surface) }
}

enum AeroSurface: Sendable { case map, strip }

private struct AeroLookKey: EnvironmentKey {
    static let defaultValue = AeroLook(palette: AeroControlPalette.of(.system, in: .dark), motion: 1)
}

extension EnvironmentValues {
    var aeroLook: AeroLook {
        get { self[AeroLookKey.self] }
        set { self[AeroLookKey.self] = newValue }
    }
}
