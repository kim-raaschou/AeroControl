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
    private static let previewCaptureSize = CGSize(width: 480, height: 320)

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
            onDismiss: { [weak self] in self?.hide() }
        )
    }

    private func hide() {
        guard requestedVisible else { return }
        requestedVisible = false
        state.clearPreviews()
        for window in windows.values { window.hideFloating() }
    }

    private func show() {
        requestedVisible = true
        if state.previewsAvailable {
            state.capturePreviews(maxSize: Self.previewCaptureSize)
        }
        if windows.isEmpty {
            rebuild()
        } else {
            for window in windows.values { window.revealFloating() }
        }
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
        for window in windows.values { window.hideFloating() }
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

    func selectEdge(_ edge: DockEdge) {
        settings.setEdge(edge)
        windows[settings.activeDisplayKey]?.applyEdge(edge)
    }

    private func makeWindow(for screen: NSScreen, hidden: Bool) {
        let availableSize = screen.visibleFrame.size
        let config = settings.config(forKey: screen.displayUUID, isBuiltin: screen.isBuiltin)
        let window = OverviewWindow(targetScreen: screen, edge: config.edge)
        window.previews = state.previewsAvailable
        let hostingView = InteractiveHostingView(rootView: makePanel(for: screen, availableSize: availableSize))
        hostingView.sizingOptions = []
        window.installFloatingContent(hosting: hostingView)
        let seed = AeroControlMetrics(iconSize: config.iconSize, previews: state.previewsAvailable).cardHeight + 4
        window.showFloating(contentSize: NSSize(width: seed, height: seed))
        if hidden { window.orderOut(nil) }
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
