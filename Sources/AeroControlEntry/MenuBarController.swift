import AppKit
import AeroControlKit

/// Owns the menu-bar control surface — the status-item menu that carries the app's
/// settings (Screen, Icon Size, Position), "Reset settings", and "Quit" — together with
/// the always-on signal triggers that toggle or quit the resident daemon. Extracted from
/// the AppDelegate so the composition root only wires and routes.
///
/// The overview is a summoned floating widget that never becomes the key/active app,
/// so it is dismissed deliberately: pressing the global toggle keybind again shows or
/// hides the single instance (a second launch of the binary signals SIGUSR1), and the
/// menu-bar icon carries a menu with icon-size + position settings, "Reset settings",
/// and "Quit" — the only surface reachable while the widget is hidden. SIGTERM/SIGINT
/// stay wired to a clean quit so a logout or `kill` still terminates the app — toggle
/// and quit are kept as distinct signals.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let onQuit: () -> Void
    /// Shows/hides the widget — the summon keybind relaunches the binary, whose
    /// second instance signals SIGUSR1 to the running one.
    private let onToggle: () -> Void
    /// Docks the widget to a screen edge (Position menu) — snaps it to that edge and
    /// sets the matching orientation for the active display.
    private let onSelectEdge: (DockEdge) -> Void
    /// Moves the widget to another display (Screen menu), applying that display's own
    /// edge/icon-size config.
    private let onSelectScreen: (NSScreen) -> Void
    /// Toggles the "show on every display" mode.
    private let onToggleMultiScreen: () -> Void
    /// Rebuilds every widget after a settings reset, so all displays re-snap to their
    /// defaults (not just the active one).
    private let onReset: () -> Void
    /// The runtime settings edited from the menu-bar menu (icon size + position), so the
    /// menu shows the current selection and applies changes live.
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

    /// Installs the always-on signal handlers: SIGTERM/SIGINT quit, SIGUSR1 toggles.
    func install() {
        installTerminationSignalHandlers()
        installToggleSignalHandler()
    }

    /// Removes every installed trigger. Idempotent — safe to call from both the
    /// app's own `quit()` and `applicationWillTerminate`.
    func teardown() {
        for source in signalSources { source.cancel() }
        signalSources.removeAll()
    }

    /// Restores control on non-graceful termination (SIGTERM/SIGINT), e.g. a
    /// logout or `kill`, where `applicationWillTerminate` does not run. Uses
    /// `DispatchSourceSignal` so the handler runs on a normal queue (async-signal
    /// safe), not in signal context. `signal(_:SIG_IGN)` disables default handling.
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

    /// Handles the show/hide toggle signal. The summon keybind relaunches the binary;
    /// its second instance sends SIGUSR1 to the running one and exits. `signal(_:
    /// SIG_IGN)` disables the default action (which would terminate) before the
    /// dispatch source takes over, so the first signal can never kill the app.
    private func installToggleSignalHandler() {
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.onToggle() }
        }
        source.resume()
        signalSources.append(source)
    }

    // MARK: - Menu-bar settings menu

    /// The menu-bar (status item) menu — the app's only settings surface and the only
    /// control reachable while the widget is hidden. Leads with a disabled version row,
    /// then groups an **Icon Size** submenu (checkable presets) and **Position**
    /// (checkable Top/Bottom/Left/Right/Center, which docks the widget there and sets the
    /// matching orientation) above "Reset settings" and "Quit". Set as the menu's delegate
    /// so `menuNeedsUpdate` rebuilds it each time it opens, keeping the checkmarks current.
    func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        populate(menu)
        return menu
    }

    /// Rebuilds the menu just before it opens so its checkmarks reflect the current
    /// settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(versionHeader())
        menu.addItem(sectionHeader("Compatible with AeroSpace ≥ 0.21.1"))
        menu.addItem(.separator())

        // Screen selection: each display keeps its own edge + icon size (so the sections
        // below apply to it). In single-screen mode selecting a screen moves the widget
        // there; in multi-screen mode a widget shows on every display and selecting one
        // just chooses which display's config the sections below edit.
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

    /// A disabled, dimmed header row that labels the group of items beneath it.
    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A disabled row showing AeroControl's own release version (`v0.1.0`).
    /// AeroControl versions independently of AeroSpace; the compatible AeroSpace
    /// range is shown on the row beneath this one. Prefers the bundle's
    /// `ACReleaseVersion` (the display string, since `CFBundleShortVersionString`
    /// must stay numeric); falls back to `v` + the numeric short version, then
    /// "dev" when run unbundled.
    private func versionHeader() -> NSMenuItem {
        let info = Bundle.main.infoDictionary
        let version = (info?["ACReleaseVersion"] as? String)
            ?? (info?["CFBundleShortVersionString"] as? String).map { "v\($0)" }
            ?? "dev"
        let item = NSMenuItem(title: "AeroControl \(version)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// Human label for an icon-size preset (e.g. "Medium (32)").
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

    /// Human label for a dock position (Title-cased).
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

    /// Human label for a display. Uses the OS-provided name; when two displays share a
    /// name (identical monitors), appends a 1-based index so they stay distinguishable.
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
        // Rebuild every widget so all displays re-snap to their reset defaults (reset()
        // only updates the store; the AppKit windows are driven imperatively).
        onReset()
    }
}
