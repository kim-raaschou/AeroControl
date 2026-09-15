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

    @Test func startsEmptyAndRemembersTheActiveDisplay() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        #expect(store.activeDisplayKey.isEmpty)
        #expect(!store.multiScreenEnabled)
        store.setActiveDisplay(key: "external", isBuiltin: false)
        #expect(SettingsStore(defaults: defaults).activeDisplayKey == "external")
    }

    @Test func multiScreenPersistsAndResetTurnsItOff() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults)
        store.setMultiScreenEnabled(true)
        #expect(SettingsStore(defaults: defaults).multiScreenEnabled)
        store.reset()
        #expect(!store.multiScreenEnabled)
        #expect(!SettingsStore(defaults: defaults).multiScreenEnabled)
    }
}
