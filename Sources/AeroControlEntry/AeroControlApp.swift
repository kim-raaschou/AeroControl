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
    private var statusItem: NSStatusItem?
    private var pendingSummon: Summon?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let runner = AerospaceSocketRunner()
        let nativeSystem = NativeApiBridgeAdapter()

        state = OverviewStore(runner: runner, nativeSystem: nativeSystem)

        settings = SettingsStore()

        menuBarController = MenuBarController(onSettingsChanged: { [weak self] in self?.overlayManager.rebuild() },
                                              bridge: nativeSystem, settings: settings)

        overlayManager = OverlayWindowManager(state: state, bridge: nativeSystem, settings: settings)

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        overlayManager.toggleVisibility()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        log.notice("link: \(url.host() ?? "-", privacy: .public)")
        guard let overlayManager else { pendingSummon = Summon(url); return }
        overlayManager.toggleVisibility(Summon(url))
    }
}
