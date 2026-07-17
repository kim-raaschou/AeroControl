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

    @Test func defaultsPerDisplayType() {
        let store = SettingsStore(defaults: makeDefaults())
        // A built-in display with nothing saved defaults to a centered HUD…
        store.setActiveDisplay(key: "builtin", isBuiltin: true)
        #expect(store.edge == .center)
        #expect(store.iconSize == AeroControlMetrics.defaultIconSize)
        // …an external display defaults to the menu-bar strip.
        store.setActiveDisplay(key: "external", isBuiltin: false)
        #expect(store.edge == .menuBar)
    }

    @Test func edgesAreIndependentPerDisplay() {
        let store = SettingsStore(defaults: makeDefaults())
        store.setActiveDisplay(key: "A", isBuiltin: true)
        store.setEdge(.top)
        store.setActiveDisplay(key: "B", isBuiltin: false)
        store.setEdge(.left)
        // Each display keeps its own edge.
        store.setActiveDisplay(key: "A", isBuiltin: true)
        #expect(store.edge == .top)
        store.setActiveDisplay(key: "B", isBuiltin: false)
        #expect(store.edge == .left)
        #expect(store.orientation == .vertical)
    }

    @Test func iconSizesAreIndependentPerDisplay() {
        let store = SettingsStore(defaults: makeDefaults())
        store.setActiveDisplay(key: "A", isBuiltin: true)
        store.setIconSize(64)
        store.setActiveDisplay(key: "B", isBuiltin: false)
        store.setIconSize(32)
        store.setActiveDisplay(key: "A", isBuiltin: true)
        #expect(store.iconSize == 64)
        store.setActiveDisplay(key: "B", isBuiltin: false)
        #expect(store.iconSize == 32)
    }

    @Test func savedConfigsSurviveANewStore() {
        let defaults = makeDefaults()
        let first = SettingsStore(defaults: defaults)
        first.setActiveDisplay(key: "A", isBuiltin: true)
        first.setIconSize(64)
        first.setEdge(.right)
        // A later launch reads the saved per-display config and active display back.
        let second = SettingsStore(defaults: defaults)
        second.setActiveDisplay(key: "A", isBuiltin: true)
        #expect(second.iconSize == 64)
        #expect(second.edge == .right)
        #expect(second.orientation == .vertical)
    }

    @Test func setIconSizeClampsToRange() {
        let store = SettingsStore(defaults: makeDefaults())
        store.setActiveDisplay(key: "A", isBuiltin: true)
        store.setIconSize(1000)
        #expect(store.iconSize == SettingsStore.maxPreferredIconSize)
        store.setIconSize(1)
        #expect(store.iconSize == SettingsStore.minPreferredIconSize)
    }

    @Test func resetForgetsPerScreenConfigs() {
        let store = SettingsStore(defaults: makeDefaults())
        store.setActiveDisplay(key: "A", isBuiltin: true)
        store.setIconSize(64)
        store.setEdge(.right)
        store.reset()
        // The active display reverts to its per-type default.
        #expect(store.iconSize == AeroControlMetrics.defaultIconSize)
        #expect(store.edge == .center)
    }

    @Test func migratesLegacyGlobalOntoFirstScreen() {
        let defaults = makeDefaults()
        // Simulate a pre-per-screen install with a single global edge + icon size.
        defaults.set(Double(64), forKey: "settings.iconSize")
        defaults.set("right", forKey: "settings.edge")
        let store = SettingsStore(defaults: defaults)
        // The first selected screen inherits the legacy global settings.
        store.setActiveDisplay(key: "A", isBuiltin: true)
        #expect(store.edge == .right)
        #expect(store.iconSize == 64)
    }

    @Test func migratesLegacyOrientationKeyOntoFirstScreen() {
        let defaults = makeDefaults()
        // An even older install that only persisted the axis.
        defaults.set("vertical", forKey: "settings.orientation")
        let store = SettingsStore(defaults: defaults)
        store.setActiveDisplay(key: "A", isBuiltin: true)
        #expect(store.edge == .left)
        #expect(store.orientation == .vertical)
    }
}
