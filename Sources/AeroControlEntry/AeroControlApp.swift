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
    private var menuBarController: MenuBarController!
    private var settings: SettingsStore!
    private let instanceGuard = SingleInstanceGuard()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let lockName = "com.aerocontrol.single-instance.lock"
        guard instanceGuard.tryAcquire(name: lockName) else {
            if let pid = instanceGuard.runningInstancePID(name: lockName) {
                kill(pid, SIGUSR1)
            }
            exit(0)
        }

        signal(SIGUSR1, SIG_IGN)

        NSApp.setActivationPolicy(.accessory)

        let runner = AerospaceSocketRunner()
        let nativeSystem = NativeApiBridgeAdapter()

        state = OverviewStore(runner: runner, nativeSystem: nativeSystem)

        settings = SettingsStore()

        menuBarController = MenuBarController(
            onQuit: { [weak self] in self?.quit() },
            onToggle: { [weak self] in self?.overlayManager.toggleVisibility() },
            onSelectTheme: { [weak self] theme in self?.overlayManager.selectTheme(theme) },
            onReset: { [weak self] in self?.overlayManager.rebuild() },
            previewsAvailable: { [weak self] in self?.state.previewsAvailable ?? false },
            onRequestPreviewAccess: { [weak self] in self?.state.requestPreviewAccess() },
            settings: settings
        )

        overlayManager = OverlayWindowManager(
            state: state,
            settings: settings
        )

        installStatusItem()

        state.start()

        NSApp.activate(ignoringOtherApps: true)

        menuBarController.install()
    }

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
        item.menu = menuBarController.settingsMenu()
        statusItem = item
    }

    @MainActor private func performTeardown() {
        menuBarController?.teardown()
        state?.stop()
        overlayManager?.removeAll()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @MainActor private func quit() {
        performTeardown()
        UserDefaults.standard.synchronize()
        exit(0)
    }

    /// `open -a AeroControl` (or a Dock/Spotlight launch) while running: toggle the overview.
    /// No second process, no signal; Launch Services delivers a reopen to this instance.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlayManager.toggleVisibility()
        return false
    }

    /// `open aerocontrol://windows`: the overview opens filtered to the focused window's app —
    /// every window of the app you are in and nothing else. `aerocontrol://workspaces`, or any other
    /// URL, toggles the map. A URL reaches the running instance the way a reopen does,
    /// without a second process — and unlike a reopen it can carry a word.
    func application(_ application: NSApplication, open urls: [URL]) {
        overlayManager.toggleVisibility(urls.contains { $0.host() == "windows" } ? .focusedApp : .map)
    }

    func applicationWillTerminate(_ notification: Notification) {
        performTeardown()
    }

}
