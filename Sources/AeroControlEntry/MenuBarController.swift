import AppKit
import AeroControlKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let onQuit: () -> Void
    private let onToggle: () -> Void
    private let onSelectScreen: (NSScreen) -> Void
    private let onToggleMultiScreen: () -> Void
    private let onReset: () -> Void
    private let previewsAvailable: () -> Bool
    private let onRequestPreviewAccess: () -> Void
    private let settings: SettingsStore

    private var signalSources: [DispatchSourceSignal] = []

    init(
        onQuit: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSelectScreen: @escaping (NSScreen) -> Void,
        onToggleMultiScreen: @escaping () -> Void,
        onReset: @escaping () -> Void,
        previewsAvailable: @escaping () -> Bool,
        onRequestPreviewAccess: @escaping () -> Void,
        settings: SettingsStore
    ) {
        self.onQuit = onQuit
        self.onToggle = onToggle
        self.onSelectScreen = onSelectScreen
        self.onToggleMultiScreen = onToggleMultiScreen
        self.onReset = onReset
        self.previewsAvailable = previewsAvailable
        self.onRequestPreviewAccess = onRequestPreviewAccess
        self.settings = settings
    }

    func install() {
        installTerminationSignalHandlers()
        installToggleSignalHandler()
    }

    func teardown() {
        for source in signalSources { source.cancel() }
        signalSources.removeAll()
    }

    private func installTerminationSignalHandlers() {
        for sig in [SIGTERM, SIGINT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.onQuit() }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    private func installToggleSignalHandler() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.onToggle() }
        }
        source.resume()
        signalSources.append(source)
    }

    func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populate(menu)
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(versionHeader())
        menu.addItem(sectionHeader("Compatible with AeroSpace ≥ 0.21.1"))
        menu.addItem(.separator())

        let multi = settings.multiScreenEnabled
        let screens = NSScreen.screens
        menu.addItem(sectionHeader(multi ? "Configure Screen" : "Screen"))
        for screen in screens {
            let item = NSMenuItem(
                title: screenLabel(for: screen, among: screens),
                action: #selector(setScreenFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = screen
            item.state = screen.displayUUID == settings.activeDisplayKey ? .on : .off
            menu.addItem(item)
        }

        let multiScreenItem = NSMenuItem(
            title: "Show on All Screens",
            action: #selector(toggleMultiScreenFromMenu),
            keyEquivalent: ""
        )
        multiScreenItem.target = self
        multiScreenItem.state = multi ? .on : .off
        menu.addItem(multiScreenItem)

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Window Previews"))
        if previewsAvailable() {
            menu.addItem(sectionHeader("On — Screen Recording granted"))
        } else {
            let grant = NSMenuItem(
                title: "Enable window previews (Screen Recording)…",
                action: #selector(requestPreviewAccessFromMenu),
                keyEquivalent: ""
            )
            grant.target = self
            grant.toolTip = "Previews capture each window once when the overview opens. Without the permission the overview shows app icons."
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        let resetSettingsItem = NSMenuItem(
            title: "Reset settings",
            action: #selector(resetSettingsFromMenu),
            keyEquivalent: ""
        )
        resetSettingsItem.target = self
        menu.addItem(resetSettingsItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit AeroControl", action: #selector(quitFromMenu), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
    }

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
        let item = NSMenuItem(title: "AeroControl \(version)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func screenLabel(for screen: NSScreen, among screens: [NSScreen]) -> String {
        let name = screen.localizedName
        let sameName = screens.filter { $0.localizedName == name }
        guard sameName.count > 1,
              let position = sameName.firstIndex(where: { $0.displayUUID == screen.displayUUID }) else {
            return name
        }
        return "\(name) (\(position + 1))"
    }

    @objc private func setScreenFromMenu(_ sender: NSMenuItem) {
        guard let screen = sender.representedObject as? NSScreen else { return }
        onSelectScreen(screen)
    }

    @objc private func toggleMultiScreenFromMenu() {
        onToggleMultiScreen()
    }

    @objc private func quitFromMenu() {
        onQuit()
    }

    @objc private func requestPreviewAccessFromMenu() {
        onRequestPreviewAccess()
    }

    @objc private func resetSettingsFromMenu() {
        settings.reset()
        onReset()
    }
}
