import AeroControlKit
import AppKit
import Common

/// Owns the single floating overview window, placing it on the user-chosen *active*
/// display (from the Screen menu) at that display's configured edge. There is no
/// follow-focus: the widget stays on the selected screen. Extracted from the
/// AppDelegate so the composition root only wires and routes.
@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    /// The one overview window. It shows every workspace grouped by monitor and sits
    /// on the active display, so there are no per-monitor windows to sync.
    private var window: OverviewWindow?
    /// The panel's hosting view, kept so its available-screen extent can be refreshed
    /// when the active display changes to a differently-sized one.
    private weak var hostingView: InteractiveHostingView<AeroControlPanel>?
    /// The active screen's available extent (visibleFrame size), fed to the panel so it
    /// can shrink its icons to fit rather than overflowing a busy workspace off-screen.
    private var availableSize: NSSize = .zero
    /// The display the window currently sits on, so a redundant re-sync is a cheap
    /// no-op instead of a needless reframe.
    private var currentScreenID: CGDirectDisplayID?
    /// Fires when displays are added/removed or their geometry changes, so the widget
    /// re-clamps (or falls back off a disconnected active display).
    private var screenObserver: NSObjectProtocol?

    init(
        state: OverviewStore,
        settings: SettingsStore
    ) {
        self.state = state
        self.settings = settings
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screenParametersChanged() }
        }
    }

    /// Resolves the initial active display (a previously-selected one if still
    /// connected, otherwise the main screen) and records it so the menu, panel, and
    /// placement all agree from the first frame. Also seeds a migrated legacy config
    /// onto that screen.
    func activateInitialScreen() {
        let screen = activeScreen()
        settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
    }

    /// Builds the SwiftUI panel bound to the current state/settings and available
    /// screen extent (so it can shrink icons to fit the active display).
    private func makePanel() -> AeroControlPanel {
        AeroControlPanel(
            state: state,
            settings: settings,
            availableWidth: availableSize.width,
            availableHeight: availableSize.height
        )
    }

    /// Ensures the single overview window exists and is anchored to the active display.
    /// `force` re-clamps even when the active display id is unchanged — used on monitor
    /// (workspace-set) changes, where the *same* display's frame/visibleFrame may have
    /// shifted (resolution, arrangement, Dock/menu-bar).
    func syncWindows(force: Bool = true) {
        let screen = activeScreen()
        if let window {
            guard force || screen.displayID != currentScreenID else { return }
            availableSize = screen.visibleFrame.size
            hostingView?.rootView = makePanel()
            window.retargetFloating(to: screen)
        } else {
            window = makeFloatingWindow(screen: screen)
        }
        currentScreenID = screen.displayID
    }

    /// Shows the single panel on the main screen when the initial load failed and no
    /// AeroSpace workspaces materialized, so `state.error` is visible.
    func showErrorFallbackIfNeeded() {
        guard state.error != nil, window == nil else { return }
        let screen = activeScreen()
        window = makeFloatingWindow(screen: screen)
        currentScreenID = screen.displayID
    }

    /// Orders out and forgets the window, and stops observing screen changes (teardown).
    func removeAll() {
        window?.orderOut(nil)
        window = nil
        currentScreenID = nil
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
            self.screenObserver = nil
        }
    }

    /// Shows or hides the widget — driven by the summon keybind (a second launch of
    /// the single-instance binary signals SIGUSR1). Hiding keeps the window instance
    /// warm for an instant re-show; showing re-clamps it to the active display and
    /// fades it back in.
    func toggleVisibility() {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }
        let existed = window != nil
        // Pre-hide a reused window so re-clamping (which orders it front) can't flash
        // it at full opacity before the reveal fade.
        if existed { window?.alphaValue = 0 }
        syncWindows(force: true)
        if existed { window?.revealFloating() }
    }

    /// Selects the active display (from the Screen menu): records it (so its own edge /
    /// icon size take effect), then moves the live window there and applies that
    /// display's configured edge.
    func selectScreen(_ screen: NSScreen) {
        settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
        availableSize = screen.visibleFrame.size
        hostingView?.rootView = makePanel()
        if let window {
            window.retargetFloating(to: screen)
            window.applyEdge(settings.edge)
        } else {
            window = makeFloatingWindow(screen: screen)
        }
        currentScreenID = screen.displayID
    }

    /// Docks the widget to `edge` (chosen from the Position menu): persists the edge
    /// for the active display, then snaps the live window to it.
    func selectEdge(_ edge: DockEdge) {
        settings.setEdge(edge)
        window?.applyEdge(edge)
    }

    /// Builds the floating widget window hosting an `AeroControlPanel` that renders
    /// every workspace grouped by monitor. The hosting view self-sizes to its content
    /// and asks the window to resize; the window docks it at the configured edge (or
    /// centered).
    private func makeFloatingWindow(screen: NSScreen) -> OverviewWindow {
        availableSize = screen.visibleFrame.size
        let window = OverviewWindow(targetScreen: screen, edge: settings.edge)
        let hostingView = InteractiveHostingView(rootView: makePanel())
        hostingView.sizingOptions = [.intrinsicContentSize]
        window.installFloatingContent(hosting: hostingView)
        self.hostingView = hostingView
        // Seed a minimal on-screen size; the hosting view's first layout pass fires
        // `onContentResize` below, which re-docks it to the exact fitting size within
        // the 0.12s fade-in — so the settle isn't visible and we avoid re-deriving the
        // panel's fitting math (which lives authoritatively in AeroControlLayout).
        let seed = AeroControlMetrics(iconSize: settings.effectiveIconSize).cardHeight + 4
        window.showFloating(contentSize: NSSize(width: seed, height: seed))
        // Keep the window hugging its content as workspaces come and go. Assigned
        // after the initial placement so the first automatic layout pass can't move
        // the panel before it has been positioned.
        hostingView.onContentResize = { [weak window] size in
            window?.resizeFloating(toContent: size)
        }
        return window
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

    /// Handles display add/remove/resize. Re-resolves the active display — persisting a
    /// fallback if the selected one is gone, so a later reconnect doesn't surprise-jump
    /// the widget — and re-clamps an existing window to the (possibly new) extent.
    private func screenParametersChanged() {
        let screen = activeScreen()
        if screen.displayUUID != settings.activeDisplayKey {
            settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
        }
        guard window != nil else { return }
        availableSize = screen.visibleFrame.size
        hostingView?.rootView = makePanel()
        window?.retargetFloating(to: screen)
        window?.applyEdge(settings.edge)
        currentScreenID = screen.displayID
    }
}
