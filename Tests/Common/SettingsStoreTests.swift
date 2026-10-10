import Testing
import Foundation
@testable import AeroControlKit
import Common

@MainActor
@Suite("SettingsStore")
struct SettingsStoreTests {
    /// A throwaway `UserDefaults` suite so tests never touch the real domain.
    private func makeDefaults() -> UserDefaults {
        let suite = "settings.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func themeDefaultsToSystemAndPersists() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.theme == .system)
        let fixed = AeroControlTheme.named("tokyoNight")!
        store.theme = fixed
        #expect(SettingsStore(defaults: defaults).theme == fixed)
        store.theme = .system
        #expect(SettingsStore(defaults: defaults).theme == .system)
    }
}
