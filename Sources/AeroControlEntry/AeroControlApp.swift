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
        // A second instance (a `make run` beside the installed app) leaves at once. Launch
        // Services never starts one from a link or a reopen; those reach the running instance.
        guard instanceGuard.tryAcquire(name: "com.aerocontrol.single-instance.lock") else { exit(0) }

        NSApp.setActivationPolicy(.accessory)

        let runner = AerospaceSocketRunner()
        let nativeSystem = NativeApiBridgeAdapter()

        state = OverviewStore(runner: runner, nativeSystem: nativeSystem)

        settings = SettingsStore()

        menuBarController = MenuBarController(
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
        state?.stop()
    }

}
