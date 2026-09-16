import SwiftUI

/// The overview's colors. `system` follows macOS (accent color, appearance, frosted glass);
/// every other theme is a fixed palette that looks the same whatever the system appearance is.
///
/// A theme is six colors, not eight roles: the palettes below are the ones their own authors
/// publish, and `AeroControlPalette` derives what the overview draws from them. Adding a theme
/// is one entry in `all`, and the tests check every one of them for readable contrast.
public struct AeroControlTheme: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    /// nil means "follow macOS", the only theme that is not a fixed palette.
    let base: BasePalette?

    public static let system = AeroControlTheme(id: "system", name: "System", base: nil)

    public static let all: [AeroControlTheme] = [
        system,
        AeroControlTheme(id: "tokyoNight", name: "Tokyo Night", base: .init(
            background: 0x1A1B26, surface: 0x292E42, border: 0x414868,
            text: 0xC0CAF5, muted: 0xA9B1D6, accent: 0x7AA2F7)),
        AeroControlTheme(id: "catppuccinMocha", name: "Catppuccin Mocha", base: .init(
            background: 0x1E1E2E, surface: 0x313244, border: 0x45475A,
            text: 0xCDD6F4, muted: 0xA6ADC8, accent: 0x89B4FA)),
        AeroControlTheme(id: "catppuccinLatte", name: "Catppuccin Latte", base: .init(
            background: 0xEFF1F5, surface: 0xCCD0DA, border: 0xBCC0CC,
            // subtext1, not subtext0: subtext0 on base is 4.4:1, just under the floor.
            text: 0x4C4F69, muted: 0x5C5F77, accent: 0x1E66F5, isDark: false)),
        AeroControlTheme(id: "nord", name: "Nord", base: .init(
            background: 0x2E3440, surface: 0x3B4252, border: 0x4C566A,
            text: 0xECEFF4, muted: 0xD8DEE9, accent: 0x88C0D0)),
        AeroControlTheme(id: "gruvboxDark", name: "Gruvbox Dark", base: .init(
            background: 0x282828, surface: 0x3C3836, border: 0x665C54,
            text: 0xEBDBB2, muted: 0xA89984, accent: 0x83A598)),
        AeroControlTheme(id: "dracula", name: "Dracula", base: .init(
            background: 0x282A36, surface: 0x44475A, border: 0x6272A4,
            // Dracula's own "comment" is the muted color by name, but it is 3.0:1 on the
            // background; lifted along the same hue to clear the floor.
            text: 0xF8F8F2, muted: 0xA3ABD8, accent: 0xBD93F9)),
        AeroControlTheme(id: "rosePine", name: "Rosé Pine", base: .init(
            background: 0x191724, surface: 0x26233A, border: 0x403D52,
            text: 0xE0DEF4, muted: 0x908CAA, accent: 0xC4A7E7)),
        AeroControlTheme(id: "solarizedDark", name: "Solarized Dark", base: .init(
            background: 0x002B36, surface: 0x073642, border: 0x586E75,
            // base2 rather than base1: Solarized's own body text is 5.6:1, readable in a
            // terminal but dim for 11pt labels over a blurred desktop.
            text: 0xEEE8D5, muted: 0x93A1A1, accent: 0x268BD2)),
    ]

    public static func named(_ id: String) -> AeroControlTheme? {
        all.first { $0.id == id }
    }

    /// The appearance a fixed palette needs macOS to draw its own parts (the backdrop blur,
    /// system materials) in; nil means "follow the system", which is what `system` wants.
    public var enforcedAppearance: ColorScheme? {
        base.map { $0.isDark ? .dark : .light }
    }

    public func palette(for scheme: ColorScheme) -> AeroControlPalette {
        base.map(AeroControlPalette.init(base:)) ?? .system(scheme)
    }
}

/// A published palette, in the six roles such palettes name.
struct BasePalette: Equatable, Sendable {
    let background: UInt32
    let surface: UInt32
    let border: UInt32
    let text: UInt32
    let muted: UInt32
    let accent: UInt32
    var isDark = true
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

    init(base: BasePalette) {
        accent = Color(hex: base.accent)
        cardFill = Color(hex: base.background).opacity(0.78)
        cardBorder = Color(hex: base.border)
        badgeFill = Color(hex: base.surface)
        badgeText = Color(hex: base.muted)
        focusedBadgeText = Color(hex: base.background)
        closeButtonFill = Color(hex: base.border)
        // The backdrop lies behind every card, so it is the palette's own background, kept
        // translucent enough for the blur to read through it.
        backdrop = Color(hex: base.background).opacity(base.isDark ? 0.62 : 0.5)
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

    private init(accent: Color, cardFill: Color?, cardBorder: Color, badgeFill: Color,
                 badgeText: Color, focusedBadgeText: Color, closeButtonFill: Color, backdrop: Color) {
        self.accent = accent
        self.cardFill = cardFill
        self.cardBorder = cardBorder
        self.badgeFill = badgeFill
        self.badgeText = badgeText
        self.focusedBadgeText = focusedBadgeText
        self.closeButtonFill = closeButtonFill
        self.backdrop = backdrop
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
