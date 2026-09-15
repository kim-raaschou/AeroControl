import AeroControlKit
import AppKit
import Common

@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    private var windows: [String: OverviewWindow] = [:]
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

    func activateInitialScreen() {
        let screen = activeScreen()
        settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
    }

    private func desiredScreens() -> [NSScreen] {
        settings.multiScreenEnabled ? NSScreen.screens : [activeScreen()]
    }

    private func screenFilter(for screen: NSScreen) -> Int? {
        guard settings.multiScreenEnabled,
              let index = NSScreen.screens.firstIndex(of: screen) else { return nil }
        return index + 1
    }

    private func makePanel(for screen: NSScreen, availableSize: NSSize) -> AeroControlPanel {
        AeroControlPanel(
            state: state,
            screenFilter: screenFilter(for: screen),
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
        state.clearPreviews()
        for window in windows.values { window.dismiss() }
        guard restoreFocus, let owner = focusedWindowOwner() else { return }
        owner.activate()
    }

    private func focusedWindowOwner() -> NSRunningApplication? {
        let focused = state.model.focusedWindowId
        let window = state.model.workspaces.flatMap(\.windows).first { $0.windowId == focused }
        guard let bundleId = window?.bundleId else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    /// Like Mission Control: single-screen mode opens on the screen under the mouse.
    /// Windows are rebuilt per summon; a SwiftUI hosting view is cheap and this keeps
    /// screen changes and settings changes free of special cases.
    private func show() {
        requestedVisible = true
        if !settings.multiScreenEnabled, let screen = screenUnderMouse() {
            settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
        }
        guard state.previewsAvailable else {
            // Ask macOS for Screen Recording on the first summon without it. The system
            // shows its dialog once per app; afterwards this is a silent no-op and the
            // menu item / System Settings is the way in. Icons are shown meanwhile.
            state.requestPreviewAccess()
            rebuild()
            return
        }
        // Nothing is shown until the snapshots are in: one fade-in with the images in
        // place instead of icons that get replaced a moment later.
        Task { [weak self] in
            guard let self else { return }
            await self.state.capturePreviews(maxSize: Self.previewCaptureSize)
            guard self.requestedVisible else { return }   // toggled away while capturing
            self.rebuild()
        }
    }

    private func screenUnderMouse() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    func rebuild() {
        reconcileActiveDisplay()
        let screens = desiredScreens()
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        for screen in screens {
            makeWindow(for: screen, hidden: !requestedVisible)
        }
    }

    func showErrorFallbackIfNeeded() {
        guard state.error != nil, windows.isEmpty else { return }
        makeWindow(for: activeScreen(), hidden: false)
    }

    func removeAll() {
        for window in windows.values { window.dismiss() }
        windows.removeAll()
    }

    func toggleVisibility() {
        if requestedVisible { hide(restoreFocus: true) } else { show() }
    }

    func toggleMultiScreen() {
        settings.setMultiScreenEnabled(!settings.multiScreenEnabled)
        rebuild()
    }

    func selectScreen(_ screen: NSScreen) {
        settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
        guard !settings.multiScreenEnabled else { return }
        rebuild()
    }

    private func makeWindow(for screen: NSScreen, hidden: Bool) {
        let window = OverviewWindow(targetScreen: screen)
        window.onDismiss = { [weak self] in self?.hide(restoreFocus: true) }
        let root = OverviewRoot(
            panel: makePanel(for: screen, availableSize: screen.frame.size),
            onDismiss: { [weak self] in self?.hide(restoreFocus: true) }
        )
        let hostingView = InteractiveHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.installContent(hosting: hostingView)
        if !hidden { window.reveal() }
        windows[screen.displayUUID] = window
    }

    private func activeScreen() -> NSScreen {
        if !settings.activeDisplayKey.isEmpty,
           let match = NSScreen.screens.first(where: { $0.displayUUID == settings.activeDisplayKey }) {
            return match
        }
        return NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    private func reconcileActiveDisplay() {
        let screen = activeScreen()
        if screen.displayUUID != settings.activeDisplayKey {
            settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
        }
    }
}
