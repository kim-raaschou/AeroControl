import AppKit
import Common

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let bridge: NativeApiBridge
    private let menu = NSMenu()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    init(bridge: NativeApiBridge) {
        self.bridge = bridge
        super.init()
        menu.delegate = self
        statusItem.button?.image = NSImage(systemSymbolName: "square.grid.3x3.fill", accessibilityDescription: "AeroControl")
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(versionHeader())
        menu.addItem(sectionHeader("Compatible with AeroSpace ≥ 0.21.0"))
        menu.addItem(.separator())
        menu.addItem(item("Show overview") { NSWorkspace.shared.open(URL(string: "aerocontrol://workspaces")!) })
        menu.addItem(sectionHeader("Bind a key to: exec-and-forget open aerocontrol://workspaces"))
        if Borders.running { menu.addItem(item("Borders: match the accent") { Borders.matchAccent() }) }
        menu.addItem(.separator())
        menu.addItem(sectionHeader("Window Previews"))
        if bridge.canCapturePreviews {
            menu.addItem(sectionHeader("On — Screen Recording granted"))
        } else {
            let grant = item("Enable window previews (Screen Recording)…") {
                if !self.bridge.requestPreviewAccess() { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }
            }
            grant.toolTip = "Previews capture each window when the overview opens. Without them the tiles are plates with the app's icon and the window's title."
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        menu.addItem(item("Quit AeroControl") { NSApp.terminate(nil) })
    }

    private func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Action(run)
        return item
    }

    private final class Action { let run: () -> Void; init(_ run: @escaping () -> Void) { self.run = run } }

    @objc private func choose(_ sender: NSMenuItem) { (sender.representedObject as? Action)?.run() }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func versionHeader() -> NSMenuItem {
        let info = Bundle.main.infoDictionary
        let version = (info?["ACReleaseVersion"] as? String)
            ?? (info?["CFBundleShortVersionString"] as? String).map { "v\($0)" }
            ?? "dev"
        return sectionHeader("AeroControl \(version)")
    }

}
