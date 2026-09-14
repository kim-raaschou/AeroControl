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
            settings: settings,
            displayKey: screen.displayUUID,
            displayIsBuiltin: screen.isBuiltin,
            screenFilter: screenFilter(for: screen),
            availableWidth: availableSize.width,
            availableHeight: availableSize.height,
            fullscreen: true,
            onDismiss: { [weak self] in self?.hide() }
        )
    }

    private func hide() {
        guard requestedVisible else { return }
        requestedVisible = false
        state.clearPreviews()
        for window in windows.values { window.dismiss() }
    }

    /// Like Mission Control: single-screen mode opens on the screen under the mouse.
    /// Windows are rebuilt per summon; a SwiftUI hosting view is cheap and this keeps
    /// screen changes and settings changes free of special cases.
    private func show() {
        requestedVisible = true
        if state.previewsAvailable {
            state.capturePreviews(maxSize: Self.previewCaptureSize)
        }
        if !settings.multiScreenEnabled, let screen = screenUnderMouse() {
            settings.setActiveDisplay(key: screen.displayUUID, isBuiltin: screen.isBuiltin)
        }
        rebuild()
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
        if requestedVisible { hide() } else { show() }
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

    /// Only the orientation of the card row (horizontal/vertical) matters in the
    /// full-screen presentation; the panel observes settings and re-lays out itself.
    func selectEdge(_ edge: DockEdge) {
        settings.setEdge(edge)
    }

    private func makeWindow(for screen: NSScreen, hidden: Bool) {
        let window = OverviewWindow(targetScreen: screen)
        window.previews = state.previewsAvailable
        window.onDismiss = { [weak self] in self?.hide() }
        let root = OverviewRoot(
            panel: makePanel(for: screen, availableSize: screen.frame.size),
            onDismiss: { [weak self] in self?.hide() }
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
