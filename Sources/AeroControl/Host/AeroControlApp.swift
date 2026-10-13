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
    private var hint: KeyHint!
    private var pendingSummon: Summon?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let runner = AerospaceSocketRunner()
        let nativeSystem = NativeApiBridgeAdapter()

        state = OverviewStore(runner: runner, nativeSystem: nativeSystem)
        hint = KeyHint(runner: runner)
        state.onEvent = { [weak self] in self?.hint.heard($0) }
        menuBarController = MenuBarController(onSettingsChanged: { [weak self] in self?.overlayManager.rebuild(); self?.hint.refresh() },
                                              bridge: nativeSystem)

        overlayManager = OverlayWindowManager(state: state)

        state.startListening()

        NSApp.activate(ignoringOtherApps: true)

        if let summon = pendingSummon {
            pendingSummon = nil
            state.summon(summon)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        state.summon(.map)
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        log.notice("link: \(url.host() ?? "-", privacy: .public)")
        if url.host() == "config" { hint?.toggle(); return }
        guard let state else { pendingSummon = Summon(url); return }
        state.summon(Summon(url))
    }
}
