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
        #expect(AeroControlTheme.system.enforcedAppearance == nil)
    }

    @Test("a fixed palette ignores the appearance and pins the one macOS draws in")
    func fixedPalettesAreFixed() {
        for theme in AeroControlTheme.all where theme != .system {
            let light = theme.palette(for: .light), dark = theme.palette(for: .dark)
            #expect(light.cardFill != nil, "\(theme.name) should paint its own card")
            #expect(light.accent == dark.accent, "\(theme.name) should not follow the appearance")
            #expect(theme.enforcedAppearance != nil, "\(theme.name) must pin an appearance")
        }
    }

    /// The reason the palettes are stored as six published colors: every theme can be held to
    /// the same floor, so a new one cannot ship with text nobody can read.
    @Test("every theme keeps text, secondary text and the accent readable on its own card")
    func everyThemeIsReadable() {
        for theme in AeroControlTheme.all {
            guard let base = theme.base else { continue }             // system: macOS's own colors
            #expect(contrast(base.text, on: base.background) >= 7, "\(theme.name) text")
            #expect(contrast(base.muted, on: base.background) >= 4.5, "\(theme.name) secondary text")
            #expect(contrast(base.accent, on: base.background) >= 3, "\(theme.name) accent")
            #expect(contrast(base.background, on: base.accent) >= 3, "\(theme.name) focused badge digit")
        }
    }

    @Test("themes are identified by a stable id, and the stored one round-trips")
    func idsAreStable() {
        #expect(AeroControlTheme.all.count >= 8)
        #expect(Set(AeroControlTheme.all.map(\.id)).count == AeroControlTheme.all.count)
        for theme in AeroControlTheme.all {
            #expect(AeroControlTheme.named(theme.id) == theme)
            #expect(!theme.name.isEmpty)
        }
        #expect(AeroControlTheme.named("nope") == nil)               // a removed theme falls back
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
