import AppKit
import AeroControlKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let onQuit: () -> Void
    private let onToggle: () -> Void
    private let onSelectEdge: (DockEdge) -> Void
    private let onSelectScreen: (NSScreen) -> Void
    private let onToggleMultiScreen: () -> Void
    private let onReset: () -> Void
    private let settings: SettingsStore

    private var signalSources: [DispatchSourceSignal] = []

    init(
        onQuit: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSelectEdge: @escaping (DockEdge) -> Void,
        onSelectScreen: @escaping (NSScreen) -> Void,
        onToggleMultiScreen: @escaping () -> Void,
        onReset: @escaping () -> Void,
        settings: SettingsStore
    ) {
        self.onQuit = onQuit
        self.onToggle = onToggle
        self.onSelectEdge = onSelectEdge
        self.onSelectScreen = onSelectScreen
        self.onToggleMultiScreen = onToggleMultiScreen
        self.onReset = onReset
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
        menu.addItem(sectionHeader("Icon Size"))
        for preset in SettingsStore.iconSizePresets {
            let item = NSMenuItem(
                title: iconSizeLabel(for: preset),
                action: #selector(setIconSizeFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = Int(preset)
            item.state = abs(settings.iconSize - preset) < 0.5 ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Position"))
        for edge in DockEdge.allCases {
            let item = NSMenuItem(
                title: edgeLabel(for: edge),
                action: #selector(setPositionFromMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = edge.rawValue
            item.state = settings.edge == edge ? .on : .off
            menu.addItem(item)
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

    private func iconSizeLabel(for preset: CGFloat) -> String {
        let name: String
        switch preset {
        case ...16: name = "Extra Small"
        case ...24: name = "Small"
        case ...32: name = "Medium"
        case ...48: name = "Large"
        default: name = "Extra Large"
        }
        return "\(name) (\(Int(preset)))"
    }

    private func edgeLabel(for edge: DockEdge) -> String {
        switch edge {
        case .top: return "Top"
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        case .center: return "Center"
        case .menuBar: return "Menu Bar"
        }
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

    @objc private func setIconSizeFromMenu(_ sender: NSMenuItem) {
        settings.setIconSize(CGFloat(sender.tag))
    }

    @objc private func setPositionFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let edge = DockEdge(rawValue: raw) else { return }
        onSelectEdge(edge)
    }

    @objc private func quitFromMenu() {
        onQuit()
    }

    @objc private func resetSettingsFromMenu() {
        settings.reset()
        onReset()
    }
}
