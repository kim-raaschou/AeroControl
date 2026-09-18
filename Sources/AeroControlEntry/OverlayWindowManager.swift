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
    /// Previews are captured to fit this box (points); tiles are drawn at 3:2 of the icon size.
    private static let previewCaptureSize = CGSize(width: 720, height: 480)

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
        window?.dismiss()
        guard restoreFocus, let owner = focusedWindowOwner() else { return }
        owner.activate()
    }

    private func focusedWindowOwner() -> NSRunningApplication? {
        owner(ofWindow: state.model.focusedWindowId)
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

    /// Type-to-filter: a keystroke the filter has a use for is consumed, anything else is
    /// handed back to the window, so Escape on an empty query still dismisses.
    private func handleKey(_ key: FilterKey) -> Bool {
        guard requestedVisible else { return false }
        switch filterKeyAction(query: state.filter, matches: state.filterMatches, selection: state.selection, key: key) {
        case .none:
            return false
        case .setQuery(let query):
            state.filter = query
            return true
        case .select(let index):
            state.selection = index
            return true
        case .focus(let windowId):
            Task { [state] in await state.dispatch(.focusWindow(windowId)) }
            hide(restoreFocus: false)       // the filter chose a window; it gets the keyboard
            return true
        }
    }

    /// The window is rebuilt per summon; a SwiftUI hosting view is cheap and this keeps
    /// display changes and settings changes free of special cases.
    private func show() {
        requestedVisible = true
        // Read AeroSpace's whole state, then snapshot what it listed, then follow it live
        // for as long as the overview is up. Nothing is drawn until both are in: one
        // fade-in with the real state and the images already in place.
        Task { [weak self] in
            guard let self else { return }
            await self.state.reload()
            guard self.requestedVisible else { return }   // toggled away while loading
            if self.state.previewsAvailable {
                await self.state.capturePreviews(maxSize: Self.previewCaptureSize)
                guard self.requestedVisible else { return }
            } else {
                // Ask macOS for Screen Recording on the first summon without it. The system
                // shows its dialog once per app; afterwards this is a silent no-op and the
                // menu item / System Settings is the way in. Icons are shown meanwhile.
                self.state.requestPreviewAccess()
            }
            self.state.startFollowingAerospace()
            self.rebuild()
        }
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

    func toggleVisibility() {
        if requestedVisible { hide(restoreFocus: true) } else { show() }
    }

    func selectTheme(_ theme: AeroControlTheme) {
        settings.setTheme(theme)
        rebuild()
    }

    private func makeWindow(for screen: NSScreen, hidden: Bool) -> OverviewWindow {
        let window = OverviewWindow(targetScreen: screen)
        window.applyAppearance(settings.theme.enforcedAppearance)
        window.onDismiss = { [weak self] in self?.hide(restoreFocus: true) }
        window.onQuitPointedApp = { [weak self] in self?.quitPointedApp() }
        window.onKey = { [weak self] in self?.handleKey($0) ?? false }
        let root = OverviewRoot(
            panel: makePanel(availableSize: screen.frame.size),
            theme: settings.theme,
            onDismiss: { [weak self] in self?.hide(restoreFocus: true) }
        )
        let hostingView = InteractiveHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.installContent(hosting: hostingView)
        if !hidden { window.reveal() }
        return window
    }
}
