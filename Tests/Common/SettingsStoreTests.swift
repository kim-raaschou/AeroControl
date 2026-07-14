import Testing
import CoreGraphics
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

    @Test func seedsFromDefaultsWhenNothingSaved() {
        let store = SettingsStore(defaults: makeDefaults())
        #expect(store.iconSize == AeroControlMetrics.defaultIconSize)
        #expect(store.edge == .top)
        #expect(store.orientation == .horizontal)
    }

    @Test func savedValuesSurviveANewStore() {
        let defaults = makeDefaults()
        // First run saves 64 + right edge from the menu.
        let first = SettingsStore(defaults: defaults)
        first.setIconSize(64)
        first.setEdge(.right)
        // A later launch reads the saved choice back.
        let second = SettingsStore(defaults: defaults)
        #expect(second.iconSize == 64)
        #expect(second.edge == .right)
        #expect(second.orientation == .vertical)
    }

    @Test func setIconSizeClampsToRange() {
        let store = SettingsStore(defaults: makeDefaults())
        store.setIconSize(1000)
        #expect(store.iconSize == SettingsStore.maxPreferredIconSize)
        store.setIconSize(1)
        #expect(store.iconSize == SettingsStore.minPreferredIconSize)
    }

    @Test func edgeDrivesDerivedOrientation() {
        let store = SettingsStore(defaults: makeDefaults())  // starts .top → horizontal
        #expect(store.orientation == .horizontal)
        store.setEdge(.bottom)
        #expect(store.orientation == .horizontal)  // bottom is still horizontal
        store.setEdge(.center)
        #expect(store.orientation == .horizontal)  // centered HUD is horizontal
        store.setEdge(.left)
        #expect(store.orientation == .vertical)
        store.setEdge(.right)
        #expect(store.orientation == .vertical)
    }

    @Test func resetRevertsToDefaults() {
        let store = SettingsStore(defaults: makeDefaults())
        store.setIconSize(64)
        store.setEdge(.right)
        store.reset()
        #expect(store.iconSize == AeroControlMetrics.defaultIconSize)
        #expect(store.edge == .top)
        #expect(store.orientation == .horizontal)
    }

    @Test func migratesLegacyOrientationKeyToEdge() {
        let defaults = makeDefaults()
        // Simulate a pre-edge install that only persisted the axis.
        defaults.set("vertical", forKey: "settings.orientation")
        let store = SettingsStore(defaults: defaults)
        #expect(store.edge == .left)
        #expect(store.orientation == .vertical)
    }
}
