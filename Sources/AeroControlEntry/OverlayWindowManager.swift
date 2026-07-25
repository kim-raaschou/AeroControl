import AeroControlKit
import AppKit
import Common

@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    private var windows: [String: OverviewWindow] = [:]
    private var requestedVisible = true

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
        let screens = desiredScreens()
        let suppressed = requestedVisible ? fullscreenSuppressedDisplays(in: screens) : Set<String>()
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
        for screen in screens {
            let hidden = !requestedVisible || suppressed.contains(screen.displayUUID)
            makeWindow(for: screen, hidden: hidden)
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
        if requestedVisible {
            requestedVisible = false
            for window in windows.values { window.hideFloating() }
        } else if windows.isEmpty {
            requestedVisible = true
            rebuild()
        } else {
            requestedVisible = true
            revealNonSuppressedWindows()
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
        applyFullscreenVisibility()
    }

    func applyFullscreenVisibility() {
        guard requestedVisible else { return }
        let screens = desiredScreens()
        let suppressed = fullscreenSuppressedDisplays(in: screens)
        for screen in screens {
            guard let window = windows[screen.displayUUID] else { continue }
            if suppressed.contains(screen.displayUUID) {
                window.hideFloating()
            } else if !window.isVisible {
                window.revealFloating()
            }
        }
    }

    private func makeWindow(for screen: NSScreen, hidden: Bool) {
        let availableSize = screen.visibleFrame.size
        let config = settings.config(forKey: screen.displayUUID, isBuiltin: screen.isBuiltin)
        let window = OverviewWindow(targetScreen: screen, edge: config.edge)
        let hostingView = InteractiveHostingView(rootView: makePanel(for: screen, availableSize: availableSize))
        hostingView.sizingOptions = []
        window.installFloatingContent(hosting: hostingView)
        let seed = AeroControlMetrics(iconSize: config.iconSize).cardHeight + 4
        window.showFloating(contentSize: NSSize(width: seed, height: seed))
        if hidden { window.orderOut(nil) }
        windows[screen.displayUUID] = window
    }

    private func revealNonSuppressedWindows() {
        let suppressed = fullscreenSuppressedDisplays(in: desiredScreens())
        for screen in desiredScreens() {
            guard let window = windows[screen.displayUUID] else { continue }
            if suppressed.contains(screen.displayUUID) {
                window.hideFloating()
            } else {
                window.revealFloating()
            }
        }
    }

    private func fullscreenSuppressedDisplays(in screens: [NSScreen]) -> Set<String> {
        let ownPid = getpid()
        guard let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else {
            return []
        }

        let candidates = raw.compactMap { info -> (CGRect, pid_t)? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let ownerPid = info[kCGWindowOwnerPID as String] as? Int, ownerPid != ownPid,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  rect.width > 0, rect.height > 0 else {
                return nil
            }
            return (rect, pid_t(ownerPid))
        }

        var suppressed: Set<String> = []
        for screen in screens {
            let screenRect = screen.frame
            let screenArea = max(1, screenRect.width * screenRect.height)
            if candidates.contains(where: { rect, _ in
                let intersection = rect.intersection(screenRect)
                let covered = intersection.width > 0 && intersection.height > 0
                    ? (intersection.width * intersection.height) / screenArea
                    : 0
                return covered >= 0.92
            }) {
                suppressed.insert(screen.displayUUID)
            }
        }
        return suppressed
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
