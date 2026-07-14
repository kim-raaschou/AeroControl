import SwiftUI
import AppKit
import Common
import AeroControlKit

@main
struct AeroControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: OverviewStore!
    private var overlayManager: OverlayWindowManager!
    private var quitController: QuitTriggerController!
    private var settings: SettingsStore!
    private var outputTask: Task<Void, Never>?
    private let instanceGuard = SingleInstanceGuard()
    /// Menu-bar control surface — the resident daemon's only reachable UI while the
    /// widget is hidden (settings + Quit).
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Allow only one AeroControl instance per user. If one is already up, this
        // invocation is the summon keybind firing again: signal it to toggle its
        // visibility (SIGUSR1, not SIGTERM — quit stays a separate signal), then exit.
        let lockName = "com.aerocontrol.single-instance.lock"
        guard instanceGuard.tryAcquire(name: lockName) else {
            if let pid = instanceGuard.runningInstancePID(name: lockName) {
                kill(pid, SIGUSR1)
            }
            // Exit directly rather than NSApp.terminate(nil): the app lifecycle
            // (applicationWillTerminate) is not yet set up, so terminate would
            // run teardown against uninitialized state.
            exit(0)
        }

        // We are the sole instance. Ignore SIGUSR1 immediately: the summon keybind can
        // fire again during startup, and until the dispatch source is installed at the
        // end of launch, SIGUSR1's default disposition would terminate us instead of
        // toggling. Ignoring it early makes an early press a harmless no-op.
        signal(SIGUSR1, SIG_IGN)

        NSApp.setActivationPolicy(.accessory)

        let runner = AerospaceProcessRunnerCli()
        let nativeSystem = NativeApiBridgeAdapter()

        state = OverviewStore(runner: runner, nativeSystem: nativeSystem)

        // The menu-bar menu (persisted to UserDefaults) is the only configuration path;
        // settings are read from there, defaulting on first launch.
        settings = SettingsStore()

        quitController = QuitTriggerController(
            onQuit: { [weak self] in self?.quit() },
            // The summon keybind relaunches the binary; the second instance signals
            // SIGUSR1, which toggles the widget's visibility.
            onToggle: { [weak self] in self?.overlayManager.toggleVisibility() },
            // The menu-bar Position menu docks the widget to a screen edge
            // (top/bottom/left/right/center) and sets the matching orientation.
            onSelectEdge: { [weak self] edge in self?.overlayManager.selectEdge(edge) },
            settings: settings
        )

        overlayManager = OverlayWindowManager(
            state: state,
            settings: settings
        )

        installStatusItem()

        Task {
            await state.start()
        }

        // Consume the store's typed output channel. Reactions:
        // - .monitorsChanged: monitor changes re-sync the window.
        // - .workspaceFocused: follow focus — move the single widget to the focused
        //   monitor's screen (floating panels float above everything and never
        //   disturb window positions).
        // - .loaded: if the initial load failed, no AeroSpace monitors are known, so
        //   `syncWindows()` creates no panel and the error would be invisible. Show a
        //   fallback panel on the main screen so `state.error` is seen.
        outputTask = Task { [weak self] in
            guard let self else { return }
            for await output in self.state.outputs {
                switch output {
                case .monitorsChanged:
                    self.overlayManager.syncWindows()
                case .workspaceFocused:
                    // Follow focus: move the single widget to the focused monitor's
                    // screen (a same-screen focus change is a cheap no-op).
                    self.overlayManager.syncWindows(force: false)
                case .loaded:
                    self.overlayManager.showErrorFallbackIfNeeded()
                case .contentChanged:
                    // A same-monitor window open/close/move (or focus shift) changed the
                    // rendered model; rebuild the panel in place so it reflects reality.
                    self.overlayManager.refreshPanel()
                }
            }
        }

        NSApp.activate(ignoringOtherApps: true)

        quitController.install()
    }

    /// Installs the always-visible menu-bar icon whose menu carries the app's settings
    /// and Quit. This is the resident daemon's only reachable control surface while the
    /// widget is hidden, so it must stay present — a distinct icon, visible by default.
    @MainActor private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "square.grid.3x3.fill",
                accessibilityDescription: "AeroControl"
            )
            image?.isTemplate = true
            button.image = image
        }
        item.menu = quitController.settingsMenu()
        statusItem = item
    }

    /// Single idempotent teardown shared by `quit()` and `applicationWillTerminate`.
    /// Order: remove quit triggers → cancel the output stream consumer → stop the
    /// store → drop the overlay windows → remove the menu-bar item.
    @MainActor private func performTeardown() {
        quitController?.teardown()
        outputTask?.cancel()
        outputTask = nil
        state?.stop()
        overlayManager?.removeAll()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @MainActor private func quit() {
        performTeardown()
        // Flush persisted settings (dock edge, icon size) to disk now: `exit(0)`
        // bypasses the normal termination flush, so persist once here before exiting.
        UserDefaults.standard.synchronize()
        exit(0)
    }

    func applicationWillTerminate(_ notification: Notification) {
        performTeardown()
    }
}
