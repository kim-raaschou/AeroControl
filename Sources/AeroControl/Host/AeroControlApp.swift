import SwiftUI
import AppKit
import Common
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
    private var pendingLink: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let runner = AerospaceSocketRunner()
        let nativeSystem = NativeApiBridgeAdapter()

        state = OverviewStore(runner: runner, nativeSystem: nativeSystem)
        menuBarController = MenuBarController(bridge: nativeSystem)

        overlayManager = OverlayWindowManager(state: state)

        state.startListening()
        Borders.matchAccent()

        NSApp.activate(ignoringOtherApps: true)

        if let url = pendingLink {
            pendingLink = nil
            application(NSApp, open: [url])
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        state.summon(.map)
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        log.notice("link: \(url.host() ?? "-", privacy: .public)")
        guard let state else { pendingLink = url; return }
        state.summon(Summon(url))
    }
}
