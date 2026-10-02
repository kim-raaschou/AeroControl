import AeroControlKit
import AppKit
import Common

@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    /// The overview is one window on one screen: the one under the mouse at summon time,
    /// like Mission Control. It always lists every workspace, whichever monitor it lives on.
    private var window: OverviewWindow?
    /// One-shot overview: starts hidden, summoned by the toggle.
    private var requestedVisible = false
    init(
        state: OverviewStore,
        settings: SettingsStore
    ) {
        self.state = state
        self.settings = settings
    }

    private func makePanel(availableSize: NSSize) -> AeroControlPanel {
        AeroControlPanel(
            state: state,
            availableWidth: availableSize.width,
            availableHeight: availableSize.height,
            // What AeroSpace tiles into (no menu bar, no dock), in its coordinates: AppKit's
            // y grows upward from the main screen's bottom, AeroSpace's downward from its top.
            screenFrames: Dictionary(uniqueKeysWithValues: NSScreen.screens.enumerated().map { index, screen in
                let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
                let visible = screen.visibleFrame
                return (index + 1, CGRect(x: visible.minX, y: top - visible.maxY, width: visible.width, height: visible.height))
            }),
            onDismiss: { [weak self] in self?.hide(restoreFocus: false) }   // the action focused something
        )
    }

    /// Escape and the backdrop dismiss without choosing anything; then the keyboard goes
    /// back to the app that owns the focused window, since summoning leaves AeroControl
    /// as the frontmost app. AeroSpace cannot do this for us: the window is already its
    /// focused one, so `focus` is a no-op there.
    private func hide(restoreFocus: Bool) {
        guard requestedVisible else { return }
        requestedVisible = false
        state.stopFollowingAerospace()      // nothing to stay in sync with while hidden
        state.clearPreviews()
        state.filter = ""
        state.presentation = .map           // and the strip with it
        window?.dismiss()
        guard restoreFocus, let app = owner(ofWindow: state.model.focusedWindowId) else { return }
        app.activate()
    }

    private func owner(ofWindow windowId: Int) -> NSRunningApplication? {
        let window = state.model.workspaces.flatMap(\.windows).first { $0.windowId == windowId }
        guard let bundleId = window?.bundleId, bundleId != Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    /// Quits the app whose window the mouse is over, falling back to the focused one, and
    /// leaves the overview up so several can go in one visit. `terminate()` is the polite
    /// quit macOS sends for Cmd-Q, so an app with unsaved work still gets to ask.
    func quitPointedApp() {
        guard requestedVisible else { return }
        let target = state.hoveredWindowId ?? state.model.focusedWindowId
        guard let app = owner(ofWindow: target) else { return }
        app.terminate()
    }

    /// Type-to-filter: the store takes the keys it has a use for; the one it cannot finish —
    /// a pick — ends the visit here. Anything else is handed back to the window, so Escape on
    /// an empty query still dismisses.
    private func handleKey(_ key: FilterKey) -> Bool {
        guard requestedVisible else { return false }
        switch state.handle(key) {
        case .none:
            return false
        case .focus(let windowId):
            state.send(.action(.focusWindow(windowId)))
            hide(restoreFocus: false)       // the filter chose a window; it gets the keyboard
        case .setQuery, .select, .handled:
            break
        }
        return true
    }

    /// The window is rebuilt per summon; a SwiftUI hosting view is cheap and this keeps
    /// display changes and settings changes free of special cases.
    private func show(_ summon: Summon) {
        requestedVisible = true
        // Read AeroSpace's whole state and every window's size, reveal the grid in its
        // final shape with a plate per window, then let the pictures land one by one —
        // waiting for all of them was most of the time between keystroke and overview.
        Task { [weak self] in
            guard let self else { return }
            if case .map = summon { self.state.presentation = .map } else { self.state.presentation = .strip }
            self.state.prepareCapture()
            await self.state.reload()
            guard self.requestedVisible else { return }   // toggled away while loading
            switch summon {
            case .map: break
            case .focusedApp: guard self.carryOut(self.state.summonApp(bundleId: nil, picker: self.settings.appPicker), for: nil) else { return }
            case .app(let id): guard self.carryOut(self.state.summonApp(bundleId: id, picker: self.settings.appPicker), for: id) else { return }
            }
            if self.state.previewsAvailable {
                await self.state.measurePreviews()
                guard self.requestedVisible else { return }
            } else {
                // Ask macOS for Screen Recording on the first summon without it. The system
                // shows its dialog once per app; afterwards this is a silent no-op and the
                // menu item / System Settings is the way in. The tiles stay plates meanwhile.
                self.state.requestPreviewAccess()
            }
            self.state.startFollowingAerospace()
            self.rebuild()
            if self.state.previewsAvailable {
                // As large as a strip card draws a window on this screen, in its pixels; a tile drawn larger asks again.
                let screen = self.window?.screen ?? NSScreen.main
                let available = screen?.frame.size ?? CGSize(width: 1440, height: 900)
                let scale = screen?.backingScaleFactor ?? 2
                await self.state.capturePreviews(maxSize: AeroControlLayout.captureSize(available: available, backingScale: scale))
            }
        }
    }

    /// Does what an app summon came to; true when it is the picker, which goes on to show.
    private func carryOut(_ action: OverviewStore.AppSummon, for bundleId: String?) -> Bool {
        switch action {
        case .pick:
            return true
        case .none:
            hide(restoreFocus: true)           // opening the URL activated us; give the keyboard back
        case .focus(let windowId):
            hide(restoreFocus: false)          // what follows takes the focus itself
            state.send(.action(.focusWindow(windowId)))
        case .launch:
            hide(restoreFocus: false)
            if let bundleId { launch(bundleId) }
        }
        return false
    }

    private func targetScreen() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    func rebuild() {
        window?.orderOut(nil)
        window = makeWindow(for: targetScreen(), hidden: !requestedVisible)
    }

    func removeAll() {
        window?.dismiss()
        window = nil
    }

    /// Starts an app that has no window, as `open -b` would.
    private func launch(_ bundleId: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The summon key again while its app's strip is up moves the marking on, as Cmd-` does;
    /// any other summon while the overview is up closes it.
    func toggleVisibility(_ summon: Summon = .map) {
        guard requestedVisible else { return show(summon) }
        if let strip = state.strip {
            switch summon {
            case .app(let id) where id == strip.bundleId: return state.stepStrip()
            case .focusedApp: return state.stepStrip()
            default: break
            }
        }
        hide(restoreFocus: true)
    }

    private func makeWindow(for screen: NSScreen, hidden: Bool) -> OverviewWindow {
        let window = OverviewWindow(targetScreen: screen)
        window.applyAppearance(settings.theme.enforcedAppearance)
        window.motion = settings.animationSpeed.scale
        window.onDismiss = { [weak self] in self?.hide(restoreFocus: true) }
        window.onQuitPointedApp = { [weak self] in self?.quitPointedApp() }
        window.onKey = { [weak self] in self?.handleKey($0) ?? false }
        let root = OverviewRoot(
            panel: makePanel(availableSize: screen.frame.size),
            theme: settings.theme,
            backdropOpacity: settings.backdropOpacity,
            motion: settings.animationSpeed.scale,
            onDismiss: { [weak self] in self?.hide(restoreFocus: true) }
        )
        let hostingView = InteractiveHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.installContent(hosting: hostingView)
        if !hidden { window.reveal() }
        return window
    }
}
