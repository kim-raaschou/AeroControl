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
    /// The summon is reading AeroSpace: until it has, the model is the last visit's, and a
    /// second key decided against it focused a closed window or started an app that runs.
    private var loading = false
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

    /// Escape and the backdrop dismiss without choosing anything; then the keyboard goes
    /// back to the app that owns the focused window, since summoning leaves AeroControl
    /// as the frontmost app. AeroSpace cannot do this for us: the window is already its
    /// focused one, so `focus` is a no-op there.
    private func hide(restoreFocus: Bool) {
        guard requestedVisible else { return }
        requestedVisible = false
        // The visit ends once the window is off the screen. Ended first, the strip turned into the
        // map, backdrop and all, for the length of the fade: a blink. A summon meanwhile ends it itself.
        // The window goes with it: kept hidden, its views held every picture they last drew.
        let ended: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, !self.requestedVisible else { return }
            // The views go first: left to draw the ended visit once more, a picture's fade scaled its
            // last picture again into the cache the visit had just emptied, and it stayed there.
            self.window?.contentView = nil
            self.window = nil
            self.state.endVisit()
        }
        if let window { window.dismiss(then: ended) } else { ended() }
        guard restoreFocus, let app = owner(ofWindow: state.model.focusedWindowId) else { return }
        app.activate()
    }

    private func owner(ofWindow windowId: Int) -> NSRunningApplication? {
        let window = state.model.workspaces.flatMap(\.windows).first { $0.windowId == windowId }
        guard let bundleId = window?.bundleId, bundleId != Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    /// ⌘Q quits the app under the ring and leaves the overview up, on the map so several can go
    /// in one visit and you see each go; in the strip the app's going ends it. `terminate()` is the polite quit macOS sends for Cmd-Q, so an
    /// app with unsaved work still gets to ask.
    private func quitRingedApp() {
        guard requestedVisible, let target = state.commandTarget, let app = owner(ofWindow: target.windowId) else { return }
        app.terminate()
    }

    /// ⌘W closes the window under the ring, as its × does, and the overview stays, the strip's
    /// marking passing on to the next; with no window under the ring it closes the overview.
    private func closeRingedWindow() {
        guard let target = state.commandTarget else { return hide(restoreFocus: true) }
        state.send(.action(.closeWindow(target.windowId)))
    }

    /// Type-to-filter: the store takes the keys it has a use for; the one it cannot finish —
    /// a pick — ends the visit here. Anything else is handed back to the window, so Escape on
    /// an empty query still dismisses.
    private func handleKey(_ key: FilterKey) -> Bool {
        guard requestedVisible else { return false }
        let action = state.handle(key)
        if case .focus(let windowId) = action { state.send(.action(.focusWindow(windowId))) }   // the store ends the shot; it gets the keyboard
        return action != .none
    }

    /// The window is rebuilt per summon; a SwiftUI hosting view is cheap and this keeps
    /// display changes and settings changes free of special cases.
    private func show(_ summon: Summon) {
        state.endVisit()                                        // the last one, if it was still fading
        requestedVisible = true
        loading = true
        // Read AeroSpace's whole state and every window's size, start taking the pictures and
        // reveal the grid in its final shape a moment later, the cards landing in a wave —
        // waiting for all of them was most of the time between keystroke and overview.
        Task { [weak self] in
            guard let self else { return }
            self.state.pictures.prepare()
            await self.state.reload()
            self.loading = false
            guard self.requestedVisible else { return }   // toggled away while loading
            switch summon {
            case .map: break
            case .app(let ref): guard self.carryOut(self.state.summonApp(ref)) else { return }
            }
            if self.state.pictures.available {
                await self.state.measurePreviews()
                guard self.requestedVisible else { return }
            } else {
                // Ask macOS for Screen Recording on the first summon without it. The system
                // shows its dialog once per app; afterwards this is a silent no-op and the
                // menu item / System Settings is the way in. The tiles stay plates meanwhile.
                self.state.pictures.requestAccess()
            }
            self.state.following = true
            self.window?.orderOut(nil)
            let screen = self.targetScreen()
            let window = self.makeWindow(for: screen, hidden: true)
            self.window = window
            Task { [weak self] in
                if self?.state.pictures.available == true { try? await Task.sleep(for: Self.revealAfter) }
                guard let self, self.requestedVisible, self.window === window else { return }
                window.reveal()
            }
            // As large as the strip, or a map card, draws a window on this screen, in its pixels; a tile
            // drawn larger asks again. Without Screen Recording the capture is the bridge's to refuse.
            await self.state.capturePreviews(maxSize: AeroControlLayout.captureSize(available: screen.frame.size, backingScale: screen.backingScaleFactor,
                                                                                     workspaces: self.state.model.workspaces.count, strip: self.state.strip != nil))
        }
    }

    /// Does what an app summon came to; true when it is the strip, which goes on to show.
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

    /// Settings changed, or a notice is to be shown: the window is built again. Hidden, there is
    /// none to rebuild; the next summon builds its own.
    func rebuild() {
        guard requestedVisible else { return }
        window?.orderOut(nil)
        window = makeWindow(for: targetScreen(), hidden: false)
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
        guard !loading else { return }                          // tens of milliseconds; the first key decides
        switch summon.again(stripApp: state.strip?.app, among: state.model.workspaces.flatMap(\.windows)) {
        case .close: hide(restoreFocus: true)
        case .step: _ = state.handle(.move(.window(1)))        // the marking moves on, as Cmd-` does
        case .summon(let ref): _ = carryOut(state.summonApp(ref))
        }
    }

    private func makeWindow(for screen: NSScreen, hidden: Bool) -> OverviewWindow {
        let window = OverviewWindow(targetScreen: screen)
        // A fixed palette also needs the parts macOS draws itself — the backdrop blur, any system
        // material — in its own appearance; otherwise Tokyo Night sits on a light blur in light mode.
        window.appearance = settings.theme.enforcedAppearance.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) } ?? nil
        // What AeroSpace tiles into (no menu bar, no dock), in its coordinates: AppKit's y grows
        // upward from the main screen's bottom, AeroSpace's downward from its top.
        let screenFrames = Dictionary(uniqueKeysWithValues: NSScreen.screens.enumerated().map { index, screen in
            let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let visible = screen.visibleFrame
            return (index + 1, CGRect(x: visible.minX, y: top - visible.maxY, width: visible.width, height: visible.height))
        })
        // Motion is macOS's to set: with Reduce motion on, everything moves in one frame.
        let motion: Double = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1
        window.motion = motion
        window.onDismiss = { [weak self] in self?.hide(restoreFocus: true) }
        window.onQuitApp = { [weak self] in self?.quitRingedApp() }
        window.onCloseWindow = { [weak self] in self?.closeRingedWindow() }
        window.onKey = { [weak self] in self?.handleKey($0) ?? false }
        let root = OverviewRoot(
            state: state,
            panel: AeroControlPanel(state: state, available: screen.frame.size, screenFrames: screenFrames),
            theme: settings.theme,
            motion: motion,
            onDismiss: { [weak self] in self?.hide(restoreFocus: true) }
        )
        let hostingView = InteractiveHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        if !hidden { window.reveal() }
        return window
    }
}
