import AeroControlKit
import AppKit
import Common
import SwiftUI

/// Owns the single floating overview window, positioning it on the focused
/// monitor's screen and retargeting it as focus (or the monitor set) changes.
/// Extracted from the AppDelegate so the composition root only wires and routes.
@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    /// The one overview window. It shows every workspace grouped by monitor and
    /// follows the focused display, so there are no per-monitor windows to sync.
    private var window: OverviewWindow?
    /// The panel's hosting view, kept so its available-screen extent can be refreshed
    /// when the widget follows focus onto a differently-sized display.
    private weak var hostingView: InteractiveHostingView<AeroControlPanel>?
    /// The focused screen's available extent (visibleFrame size), fed to the panel so it
    /// can shrink its icons to fit rather than overflowing a busy workspace off-screen.
    private var availableSize: NSSize = .zero
    /// The display the window currently sits on, so a same-screen focus change is a
    /// cheap no-op instead of a needless reframe.
    private var currentScreenID: CGDirectDisplayID?

    init(
        state: OverviewStore,
        settings: SettingsStore
    ) {
        self.state = state
        self.settings = settings
    }

    /// Builds the SwiftUI panel bound to the current state/settings and available
    /// screen extent (so it can shrink icons to fit the focused display).
    private func makePanel() -> AeroControlPanel {
        AeroControlPanel(
            state: state,
            settings: settings,
            availableWidth: availableSize.width,
            availableHeight: availableSize.height
        )
    }

    /// Ensures the single overview window exists and is anchored to the focused
    /// monitor's screen. `force` retargets (and re-clamps) even when the focused
    /// display id is unchanged — used on monitor changes, where the *same* display's
    /// frame/visibleFrame may have shifted (resolution, arrangement, Dock/menu-bar).
    /// Focus changes pass `force: false`, so following focus within one display is a
    /// cheap no-op instead of a needless reframe.
    func syncWindows(force: Bool = true) {
        guard !state.model.monitors.isEmpty else { return }
        let screen = focusedScreen()
        if let window {
            guard force || screen.displayID != currentScreenID else { return }
            // The widget may have followed focus onto a differently-sized display;
            // refresh the panel's available extent so its shrink-to-fit uses the screen
            // it now sits on.
            availableSize = screen.visibleFrame.size
            hostingView?.rootView = makePanel()
            window.retargetFloating(to: screen)
        } else {
            window = makeFloatingWindow(screen: screen)
        }
        currentScreenID = screen.displayID
    }

    /// Rebuilds the panel's SwiftUI root view in place to reflect a model change,
    /// without reframing or retargeting the window. Needed because the manually-hosted
    /// `NSHostingView` doesn't auto-observe `@Observable` model changes. Skipped when the
    /// widget is hidden — a later summon re-syncs from the current model — so this never
    /// resurrects a widget the user has dismissed.
    func refreshPanel() {
        guard let window, window.isVisible else { return }
        hostingView?.rootView = makePanel()
    }

    /// Shows the single panel on the main screen when the initial load failed and no
    /// AeroSpace monitors materialized, so `state.error` is visible.
    func showErrorFallbackIfNeeded() {
        guard state.error != nil, window == nil else { return }
        let screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        window = makeFloatingWindow(screen: screen)
        currentScreenID = screen.displayID
    }

    /// Orders out and forgets the window (teardown).
    func removeAll() {
        window?.orderOut(nil)
        window = nil
        currentScreenID = nil
    }

    /// Shows or hides the widget — driven by the summon keybind (a second launch of
    /// the single-instance binary signals SIGUSR1). Hiding keeps the window instance
    /// warm for an instant re-show; showing retargets it to the focused monitor and
    /// fades it back in.
    func toggleVisibility() {
        if let window, window.isVisible {
            window.orderOut(nil)
            return
        }
        let existed = window != nil
        // Pre-hide a reused window so retargeting (which orders it front) can't flash
        // it at full opacity before the reveal fade.
        if existed { window?.alphaValue = 0 }
        syncWindows(force: true)
        if existed { window?.revealFloating() }
    }

    /// Docks the widget to `edge` (chosen from the Position menu): persists the edge
    /// (and derived orientation), then snaps the live window to it.
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
        let seed = AeroControlMetrics(iconSize: settings.iconSize).cardHeight + 4
        window.showFloating(contentSize: NSSize(width: seed, height: seed))
        // Keep the window hugging its content as workspaces come and go. Assigned
        // after the initial placement so the first automatic layout pass can't move
        // the panel before it has been positioned.
        hostingView.onContentResize = { [weak window] size in
            window?.resizeFloating(toContent: size)
        }
        return window
    }

    /// The `NSScreen` of the currently focused monitor (falls back to the lowest
    /// monitor id, then the main screen). Follows AeroSpace focus so the single
    /// widget appears where the user is working.
    private func focusedScreen() -> NSScreen {
        let focusedName = state.model.focusedWorkspace
        let monitorId = state.model.workspaces.first { $0.name == focusedName }?.monitorId
            ?? state.model.monitors.first?.monitorId
        if let monitorId {
            return screenForMonitor(MonitorInfo(monitorId: monitorId))
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    /// Maps an AeroSpace monitor to its `NSScreen`. Prefers AeroSpace's reported
    /// 1-based AppKit screen index (`monitor-appkit-nsscreen-screens-id`), which is
    /// authoritative; falls back to the `monitorId - 1` positional guess only when
    /// that mapping is unavailable (e.g. older aerospace without the field).
    private func screenForMonitor(_ monitor: MonitorInfo) -> NSScreen {
        let screens = NSScreen.screens
        if let nsscreenId = state.monitorScreenIds[monitor.monitorId] {
            let index = nsscreenId - 1
            if index >= 0, index < screens.count {
                return screens[index]
            }
        }
        let fallback = monitor.monitorId - 1
        if fallback >= 0, fallback < screens.count {
            return screens[fallback]
        }
        return NSScreen.main ?? screens.first ?? NSScreen()
    }
}
