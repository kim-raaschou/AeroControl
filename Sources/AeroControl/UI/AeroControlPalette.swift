import SwiftUI

struct AeroControlPalette: Sendable {
    let accent: Color
    let cardBorder: Color
    let badgeFill: Color
    let badgeText: Color
    let focusedBadgeText: Color
    let closeButtonFill: Color
    let backdrop: Color

    static func system(_ scheme: ColorScheme) -> AeroControlPalette {
        let dark = scheme == .dark
        return AeroControlPalette(
            accent: .accentColor,
            cardBorder: dark ? .white.opacity(0.18) : .black.opacity(0.12),
            badgeFill: dark ? .white.opacity(0.10) : .black.opacity(0.07),
            badgeText: .secondary,
            focusedBadgeText: .white,
            closeButtonFill: Color(white: dark ? 0.26 : 0.92),
            backdrop: .black.opacity(0.85)
        )
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
    static let defaultValue = AeroLook(palette: .system(.dark), motion: 1)
}

extension EnvironmentValues {
    var aeroLook: AeroLook {
        get { self[AeroLookKey.self] }
        set { self[AeroLookKey.self] = newValue }
    }
}
