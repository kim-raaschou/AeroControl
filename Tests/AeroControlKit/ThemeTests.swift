import SwiftUI
import Testing
@testable import AeroControlKit

@Suite("Theme")
struct ThemeTests {
    @Test("system follows the platform: frosted cards, the user's accent, appearance-dependent chrome")
    func systemFollowsThePlatform() {
        let light = AeroControlTheme.system.palette(for: .light)
        let dark = AeroControlTheme.system.palette(for: .dark)
        #expect(light.cardFill == nil && dark.cardFill == nil)      // nil means the frosted material
        #expect(light.accent == .accentColor)
        #expect(light.cardBorder != dark.cardBorder)
    }

    @Test("a fixed palette ignores the appearance and paints its own card")
    func tokyoNightIsFixed() {
        let light = AeroControlTheme.tokyoNight.palette(for: .light)
        let dark = AeroControlTheme.tokyoNight.palette(for: .dark)
        #expect(light.cardFill != nil)
        #expect(light.accent == dark.accent && light.cardBorder == dark.cardBorder)
        #expect(light.accent == Color(hex: 0x7AA2F7))               // Tokyo Night blue
    }

    @Test("every theme is selectable by its stored name")
    func roundTripsThroughSettings() {
        for theme in AeroControlTheme.allCases {
            #expect(AeroControlTheme(rawValue: theme.rawValue) == theme)
            #expect(!theme.name.isEmpty)
        }
        #expect(AeroControlTheme.allCases.count == 2)
    }
}
