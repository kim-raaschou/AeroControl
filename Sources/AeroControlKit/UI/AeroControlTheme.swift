import SwiftUI

/// The overview's colors. `system` follows macOS (accent color, appearance, frosted glass);
/// the others are fixed palettes that look the same in light and dark mode.
public enum AeroControlTheme: String, CaseIterable, Sendable {
    case system
    case tokyoNight

    public var name: String {
        switch self {
        case .system: "System"
        case .tokyoNight: "Tokyo Night"
        }
    }

    public func palette(for scheme: ColorScheme) -> AeroControlPalette {
        switch self {
        case .system: .system(scheme)
        case .tokyoNight: .tokyoNight
        }
    }
}

/// Every color the overview draws. `cardFill` is nil when the card should use the platform's
/// frosted material instead of a solid color.
public struct AeroControlPalette: Sendable {
    public let accent: Color
    public let cardFill: Color?
    public let cardBorder: Color
    public let badgeFill: Color
    public let badgeText: Color
    public let focusedBadgeText: Color
    public let closeButtonFill: Color
    public let backdrop: Color

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

    /// Tokyo Night (the "night" variant), by the palette's own names:
    /// bg #1a1b26, bg_highlight #292e42, border #414868, fg #c0caf5, comment #565f89, blue #7aa2f7.
    static let tokyoNight = AeroControlPalette(
        accent: Color(hex: 0x7AA2F7),
        cardFill: Color(hex: 0x1A1B26).opacity(0.92),
        cardBorder: Color(hex: 0x414868),
        badgeFill: Color(hex: 0x292E42),
        badgeText: Color(hex: 0x565F89),
        focusedBadgeText: Color(hex: 0x1A1B26),
        closeButtonFill: Color(hex: 0x414868),
        backdrop: Color(hex: 0x16161E).opacity(0.62)
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// The theme every overview view draws with; the host sets it once on the root.
/// (A plain `EnvironmentKey`: SwiftUI's `@Entry` macro needs a plugin the Command Line
/// Tools toolchain does not ship.)
private struct AeroThemeKey: EnvironmentKey {
    static let defaultValue: AeroControlTheme = .system
}

public extension EnvironmentValues {
    var aeroTheme: AeroControlTheme {
        get { self[AeroThemeKey.self] }
        set { self[AeroThemeKey.self] = newValue }
    }
}
