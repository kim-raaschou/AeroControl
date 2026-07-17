import AeroControlKit
import AppKit
import Common

/// Owns the floating overview window(s). By default a single widget sits on the
/// user-chosen *active* display (from the Screen menu) at that display's configured
/// edge — there is no follow-focus. When the "Show on All Screens" option
/// is on, one widget is placed on *every* connected display, each rendering its own
/// display's config. Extracted from the AppDelegate so the composition root only wires.
@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    /// One live overview window per display it is shown on, keyed by the display's
    /// persistence-stable `displayUUID`. Single-screen mode holds exactly one entry (the
    /// active display); multi-screen mode holds one per `NSScreen`.
    private var windows: [String: OverviewWindow] = [:]

    init(
        state: OverviewStore,
        settings: SettingsStore
    ) {
        self.state = state
        self.settings = settings
    }

    /// Resolves the initial active display (a previously-selected one if still
    /// connected, otherwise the main screen) and records it so the menu, panel, and
    /// placement all agree from the first frame. Also seeds a migrated legacy config
    /// onto that screen.
    func activateInitialScreen() {
        let screen = activeScreen()
        settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
    }

    /// The displays the widget should currently occupy: every connected screen in
    /// multi-screen mode, otherwise just the single active display.
    private func desiredScreens() -> [NSScreen] {
        settings.multiScreenEnabled ? NSScreen.screens : [activeScreen()]
    }

    /// The 1-based `NSScreen.screens` index of `screen`, matching AeroSpace's
    /// `monitor-appkit-nsscreen-screens-id`. Feeds the per-screen widget's filter so it
    /// shows exactly the workspaces AeroSpace reports on this physical display. Only
    /// applied in multi-screen mode; single mode shows every monitor grouped.
    private func screenFilter(for screen: NSScreen) -> Int? {
        guard settings.multiScreenEnabled,
              let index = NSScreen.screens.firstIndex(of: screen) else { return nil }
        return index + 1
    }

    /// Builds the SwiftUI panel bound to a specific display, so each window renders that
    /// display's own edge/icon-size config and can shrink icons to fit its extent.
    private func makePanel(for screen: NSScreen, availableSize: NSSize) -> AeroControlPanel {
        AeroControlPanel(
            state: state,
            settings: settings,
            displayKey: screen.displayUUID,
            displayIsBuiltin: screen.isBuiltin,
            screenFilter: screenFilter(for: screen),
            availableWidth: availableSize.width,
            availableHeight: availableSize.height
        )
    }

    /// Rebuilds every widget from scratch: orders out and forgets all live windows, then
    /// creates one fresh window per desired display. Every structural change routes here —
    /// there is no incremental reconcile. Crucially, monitor add/remove is *also* an
    /// AeroSpace event: it re-homes workspaces, the derived monitor set changes, and the
    /// store fires `onMonitorsChanged` → here. So AeroSpace's stream is the single trusted
    /// source for display changes — no separate `NSScreen` observer to double-source it.
    /// First re-resolves the active display (persisting a fallback if the selected one is
    /// gone). A summon-hidden state is preserved so a rebuild can't resurrect a dismissed
    /// overlay.
    func rebuild() {
        reconcileActiveDisplay()
        let hidden = !windows.isEmpty && windows.values.allSatisfy { !$0.isVisible }
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        for screen in desiredScreens() { makeWindow(for: screen, hidden: hidden) }
    }

    /// Shows a panel on the active screen when the initial load failed and no AeroSpace
    /// workspaces materialized, so `state.error` is visible.
    func showErrorFallbackIfNeeded() {
        guard state.error != nil, windows.isEmpty else { return }
        makeWindow(for: activeScreen(), hidden: false)
    }

    /// Orders out and forgets every window (teardown).
    func removeAll() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    /// Shows or hides the widget(s) — driven by the summon keybind (a second launch of
    /// the single-instance binary signals SIGUSR1). Hiding keeps the windows warm for an
    /// instant re-show; showing fades the warm windows back in (rebuilding only if none
    /// exist yet). A background screen-change rebuild keeps warm windows on the right
    /// displays while hidden, so re-show needs no re-clamp.
    func toggleVisibility() {
        if windows.values.contains(where: { $0.isVisible }) {
            for window in windows.values { window.orderOut(nil) }
        } else if windows.isEmpty {
            rebuild()
        } else {
            for window in windows.values { window.revealFloating() }
        }
    }

    /// Toggles the "show on every display" mode and rebuilds to the new set.
    func toggleMultiScreen() {
        settings.setMultiScreenEnabled(!settings.multiScreenEnabled)
        rebuild()
    }

    /// Selects the active display (from the Screen menu). In single-screen mode this
    /// rebuilds the one widget onto the chosen display at its configured edge. In
    /// multi-screen mode every display already shows a widget, so this only changes which
    /// display the Icon Size / Position sections edit (the active display).
    func selectScreen(_ screen: NSScreen) {
        settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
        guard !settings.multiScreenEnabled else { return }
        rebuild()
    }

    /// Docks the widget to `edge` (chosen from the Position menu): persists the edge for
    /// the active display, then snaps that display's live window to it.
    func selectEdge(_ edge: DockEdge) {
        settings.setEdge(edge)
        windows[settings.activeDisplayKey]?.applyEdge(edge)
    }

    /// Builds and stores a floating widget window for `screen`, hosting an
    /// `AeroControlPanel` bound to that display. The hosting view self-sizes to its
    /// content and asks the window to resize; the window docks it at the display's
    /// configured edge. Created hidden when `hidden` — so a rebuild while summon-hidden
    /// doesn't resurrect the overlay.
    private func makeWindow(for screen: NSScreen, hidden: Bool) {
        let availableSize = screen.visibleFrame.size
        let config = settings.config(forKey: screen.displayUUID, isBuiltin: screen.isBuiltin)
        let window = OverviewWindow(targetScreen: screen, edge: config.edge)
        let hostingView = InteractiveHostingView(rootView: makePanel(for: screen, availableSize: availableSize))
        hostingView.sizingOptions = [.intrinsicContentSize]
        window.installFloatingContent(hosting: hostingView)
        // Seed a minimal on-screen size; the hosting view's first layout pass fires
        // `onContentResize` below, which re-docks it to the exact fitting size within the
        // fade-in — so the settle isn't visible and we avoid re-deriving the panel's
        // fitting math (which lives authoritatively in AeroControlLayout).
        let seed = AeroControlMetrics(iconSize: config.iconSize).cardHeight + 4
        window.showFloating(contentSize: NSSize(width: seed, height: seed))
        hostingView.onContentResize = { [weak window] size in
            window?.resizeFloating(toContent: size)
        }
        if hidden { window.orderOut(nil) }
        windows[screen.displayUUID] = window
    }

    /// The `NSScreen` for the active display: the previously-selected one if still
    /// connected, otherwise the main screen (then any screen). Never follows focus.
    private func activeScreen() -> NSScreen {
        if !settings.activeDisplayKey.isEmpty,
           let match = NSScreen.screens.first(where: { $0.displayUUID == settings.activeDisplayKey }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// Re-resolves the active display and persists a fallback if the previously-selected
    /// one has disconnected, so a later reconnect doesn't surprise-jump the widget and the
    /// edge/config menus keep editing a live display. Called at the top of every rebuild.
    private func reconcileActiveDisplay() {
        let screen = activeScreen()
        if screen.displayUUID != settings.activeDisplayKey {
            settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
        }
    }
}
