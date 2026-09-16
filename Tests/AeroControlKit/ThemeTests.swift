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

    @Test("a fixed palette keeps small text readable and pins the appearance macOS draws in")
    func fixedThemeIsReadableAndPinned() {
        #expect(AeroControlTheme.system.enforcedAppearance == nil)          // follows macOS
        #expect(AeroControlTheme.tokyoNight.enforcedAppearance == .dark)
        // Secondary text on the card: 4.5:1 is the floor for small text.
        #expect(contrast(0xA9B1D6, on: 0x1A1B26) > 4.5)
        #expect(contrast(0x565F89, on: 0x1A1B26) < 4.5)                     // the palette's own comment color
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

/// WCAG relative-luminance contrast ratio, so a palette change cannot quietly make text
/// unreadable again.
private func contrast(_ a: UInt32, on b: UInt32) -> Double {
    func luminance(_ hex: UInt32) -> Double {
        func channel(_ c: UInt32) -> Double {
            let v = Double(c) / 255
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel((hex >> 16) & 255)
             + 0.7152 * channel((hex >> 8) & 255)
             + 0.0722 * channel(hex & 255)
    }
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}
