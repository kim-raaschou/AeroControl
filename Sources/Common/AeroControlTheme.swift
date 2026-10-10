import Foundation

public struct AeroControlTheme: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let base: BasePalette?

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
            text: 0x4C4F69, muted: 0x5C5F77, accent: 0x1E66F5, isDark: false)),
        AeroControlTheme(id: "nord", name: "Nord", base: .init(
            background: 0x2E3440, surface: 0x3B4252, border: 0x4C566A,
            text: 0xECEFF4, muted: 0xD8DEE9, accent: 0x88C0D0)),
        AeroControlTheme(id: "gruvboxDark", name: "Gruvbox Dark", base: .init(
            background: 0x282828, surface: 0x3C3836, border: 0x665C54,
            text: 0xEBDBB2, muted: 0xA89984, accent: 0x83A598)),
        AeroControlTheme(id: "dracula", name: "Dracula", base: .init(
            background: 0x282A36, surface: 0x44475A, border: 0x6272A4,
            text: 0xF8F8F2, muted: 0xA3ABD8, accent: 0xBD93F9)),
        AeroControlTheme(id: "rosePine", name: "Rosé Pine", base: .init(
            background: 0x191724, surface: 0x26233A, border: 0x403D52,
            text: 0xE0DEF4, muted: 0x908CAA, accent: 0xC4A7E7)),
        AeroControlTheme(id: "solarizedDark", name: "Solarized Dark", base: .init(
            background: 0x002B36, surface: 0x073642, border: 0x586E75,
            text: 0xEEE8D5, muted: 0x93A1A1, accent: 0x268BD2)),
    ]

    public static func named(_ id: String) -> AeroControlTheme? {
        all.first { $0.id == id }
    }

    public var isDark: Bool? { base.map(\.isDark) }
}

public struct BasePalette: Equatable, Sendable {
    public let background: UInt32
    public let surface: UInt32
    public let border: UInt32
    public let text: UInt32
    public let muted: UInt32
    public let accent: UInt32
    public var isDark = true
}
