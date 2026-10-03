import SwiftUI
import AppKit
import Common
import AeroControlKit
import OSLog

private let log = Logger(subsystem: "com.aerocontrol.AeroControl", category: "overview")

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
    /// The link that started the app: AppKit delivers it before `applicationDidFinishLaunching`,
    /// when nothing is built yet, so it waits here until the end of that.
    private var pendingSummon: Summon?

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
            onSettingsChanged: { [weak self] in self?.overlayManager.rebuild() },
            previewsAvailable: { [weak self] in self?.state.previewsAvailable ?? false },
            onRequestPreviewAccess: { [weak self] in self?.state.requestPreviewAccess() },
            settings: settings
        )

        overlayManager = OverlayWindowManager(
            state: state,
            settings: settings
        )

        installStatusItem()

        state.startListening()

        NSApp.activate(ignoringOtherApps: true)

        menuBarController.install()

        if let summon = pendingSummon {
            pendingSummon = nil
            overlayManager.toggleVisibility(summon)
        }
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
    /// every window of the app you are in and nothing else. `aerocontrol://workspaces`, or any
    /// other link, toggles the map.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        log.notice("link: \(url.host() ?? "-", privacy: .public)")
        // Started by the link, the app has no overlay yet: the summon is carried out when it has.
        guard let overlayManager else { pendingSummon = Summon(url); return }
        overlayManager.toggleVisibility(Summon(url))
    }

    func applicationWillTerminate(_ notification: Notification) {
        performTeardown()
    }

}
