import AeroControlKit
import AppKit
import Common

@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    private var windows: [String: OverviewWindow] = [:]

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
            availableHeight: availableSize.height
        )
    }

    func rebuild() {
        reconcileActiveDisplay()
        let hidden = !windows.isEmpty && windows.values.allSatisfy { !$0.isVisible }
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        for screen in desiredScreens() { makeWindow(for: screen, hidden: hidden) }
    }

    func showErrorFallbackIfNeeded() {
        guard state.error != nil, windows.isEmpty else { return }
        makeWindow(for: activeScreen(), hidden: false)
    }

    func removeAll() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    func toggleVisibility() {
        if windows.values.contains(where: { $0.isVisible }) {
            for window in windows.values { window.orderOut(nil) }
        } else if windows.isEmpty {
            rebuild()
        } else {
            for window in windows.values { window.revealFloating() }
        }
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
        let hostingView = InteractiveHostingView(rootView: makePanel(for: screen, availableSize: availableSize))
        hostingView.sizingOptions = [.intrinsicContentSize]
        window.installFloatingContent(hosting: hostingView)
        let seed = AeroControlMetrics(iconSize: config.iconSize).cardHeight + 4
        window.showFloating(contentSize: NSSize(width: seed, height: seed))
        hostingView.onContentResize = { [weak window] size in
            window?.resizeFloating(toContent: size)
        }
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
