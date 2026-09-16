import Testing
import Foundation
@testable import AeroControlKit

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
        store.setTheme(.tokyoNight)
        #expect(SettingsStore(defaults: defaults).theme == .tokyoNight)
        store.reset()
        #expect(store.theme == .system)
        #expect(SettingsStore(defaults: defaults).theme == .system)
    }

    @Test func resetClearsTheKeysOfOlderVersions() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: "settings.multiScreenEnabled")
        defaults.set("uuid", forKey: "settings.activeDisplay")
        SettingsStore(defaults: defaults).reset()
        #expect(defaults.object(forKey: "settings.multiScreenEnabled") == nil)
        #expect(defaults.object(forKey: "settings.activeDisplay") == nil)
    }
}
