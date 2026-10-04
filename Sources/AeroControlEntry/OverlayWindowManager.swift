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
    /// The overview is shown this long after its pictures start being taken, so the first cards
    /// are about to land: shown at once, its plates stood empty for 230 ms.
    private static let revealAfter: Duration = .milliseconds(120)
    init(
        state: OverviewStore,
        settings: SettingsStore
    ) {
        self.state = state
        self.settings = settings
        // The overview took the keyboard back when AeroSpace focused the app: give it to the app.
        state.onShotDone = { [weak self] in self?.hide(restoreFocus: $0) }
    }

    private func makePanel(availableSize: NSSize) -> AeroControlPanel {
        // What AeroSpace tiles into (no menu bar, no dock), in its coordinates: AppKit's y grows
        // upward from the main screen's bottom, AeroSpace's downward from its top.
        let screenFrames = Dictionary(uniqueKeysWithValues: NSScreen.screens.enumerated().map { index, screen in
            let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let visible = screen.visibleFrame
            return (index + 1, CGRect(x: visible.minX, y: top - visible.maxY, width: visible.width, height: visible.height))
        })
        return AeroControlPanel(
            state: state,
            availableWidth: availableSize.width,
            availableHeight: availableSize.height,
            screenFrames: screenFrames
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
        state.dropStrip()
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
            state.send(.action(.focusWindow(windowId)))     // the store ends the shot; it gets the keyboard
        case .setQuery, .handled:
            break
        }
        return true
    }

    /// The window is rebuilt per summon; a SwiftUI hosting view is cheap and this keeps
    /// display changes and settings changes free of special cases.
    private func show(_ summon: Summon) {
        requestedVisible = true
        // Read AeroSpace's whole state and every window's size, start taking the pictures and
        // reveal the grid in its final shape a moment later, the cards landing in a wave —
        // waiting for all of them was most of the time between keystroke and overview.
        Task { [weak self] in
            guard let self else { return }
            self.state.prepareCapture()
            await self.state.reload()
            guard self.requestedVisible else { return }   // toggled away while loading
            switch summon {
            case .map: break
            case .app(let ref): guard self.carryOut(self.state.summonApp(ref, picker: self.settings.appPicker)) else { return }
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
            self.window?.orderOut(nil)
            let screen = self.targetScreen()
            let window = self.makeWindow(for: screen, hidden: true)
            self.window = window
            Task { [weak self] in
                if self?.state.previewsAvailable == true { try? await Task.sleep(for: Self.revealAfter) }
                guard let self, self.requestedVisible, self.window === window else { return }
                window.reveal()
            }
            if self.state.previewsAvailable {
                // As large as a strip card draws a window on this screen, in its pixels; a tile drawn larger asks again.
                await self.state.capturePreviews(maxSize: AeroControlLayout.captureSize(available: screen.frame.size, backingScale: screen.backingScaleFactor))
            }
        }
    }

    /// Does what an app summon came to; true when it is the picker, which goes on to show.
    private func carryOut(_ action: AppSummon) -> Bool {
        switch action {
        case .pick:
            return true
        case .focus(let windowId):
            state.send(.action(.focusWindow(windowId)))     // what follows takes the focus itself
        case .launch(let ref):
            hide(restoreFocus: false)
            launch(ref)
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

    /// Starts an app that has no window, with `open`: `-b` by bundle id, `-a` by name, the one
    /// lookup by name macOS offers. A name or id nothing answers to, `open` exits 1 on, and the
    /// overview comes back to say so, unless something else was summoned meanwhile.
    private func launch(_ ref: AppRef) {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        switch ref {
        case .bundleId(let id): open.arguments = ["-b", id]
        case .name(let name): open.arguments = ["-a", name]
        }
        open.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            Task { @MainActor [weak self] in
                guard let self, !self.requestedVisible else { return }
                self.requestedVisible = true
                self.state.missingApp = ref
                self.rebuild()
            }
        }
        try? open.run()
    }

    /// A summon while the overview is up: see `Summon.again`.
    func toggleVisibility(_ summon: Summon = .map) {
        guard requestedVisible else { return show(summon) }
        switch summon.again(stripApp: state.strip?.bundleId, among: state.model.workspaces.flatMap(\.windows)) {
        case .close: hide(restoreFocus: true)
        case .step: state.stepStrip()
        case .summon(let ref): _ = carryOut(state.summonApp(ref, picker: settings.appPicker))
        }
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
