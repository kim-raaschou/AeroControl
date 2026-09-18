import AppKit
import AeroControlKit

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let onQuit: () -> Void
    private let onToggle: () -> Void
    private let onSelectTheme: (AeroControlTheme) -> Void
    private let onReset: () -> Void
    private let previewsAvailable: () -> Bool
    private let onRequestPreviewAccess: () -> Void
    private let settings: SettingsStore

    private var signalSources: [DispatchSourceSignal] = []

    init(
        onQuit: @escaping () -> Void,
        onToggle: @escaping () -> Void,
        onSelectTheme: @escaping (AeroControlTheme) -> Void,
        onReset: @escaping () -> Void,
        previewsAvailable: @escaping () -> Bool,
        onRequestPreviewAccess: @escaping () -> Void,
        settings: SettingsStore
    ) {
        self.onQuit = onQuit
        self.onToggle = onToggle
        self.onSelectTheme = onSelectTheme
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
        menu.addItem(sectionHeader("Compatible with AeroSpace ≥ 0.21.0"))
        menu.addItem(.separator())
        // A submenu, not nine items: the palette list would otherwise be most of the menu.
        // The parent carries the current theme's name and swatch, so the choice is visible
        // without opening it.
        let themeItem = NSMenuItem(title: "Theme: \(settings.theme.name)", action: nil, keyEquivalent: "")
        themeItem.image = swatch(for: settings.theme)
        let themeMenu = NSMenu()
        for theme in AeroControlTheme.all {
            let item = NSMenuItem(title: theme.name, action: #selector(setThemeFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = theme.id
            item.state = settings.theme == theme ? .on : .off
            item.image = swatch(for: theme)
            themeMenu.addItem(item)
        }
        themeItem.submenu = themeMenu
        menu.addItem(themeItem)

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

    /// A dot in the theme's accent on its own background, so the list can be read at a glance
    /// instead of by name alone.
    private func swatch(for theme: AeroControlTheme) -> NSImage {
        let side: CGFloat = 12
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let palette = theme.palette(for: .dark)
            (NSColor(palette.cardFill ?? .clear)).setFill()
            NSBezierPath(ovalIn: rect).fill()
            NSColor(palette.accent).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: side * 0.3, dy: side * 0.3)).fill()
            NSColor(palette.cardBorder).setStroke()
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5))
            ring.lineWidth = 1
            ring.stroke()
            return true
        }
    }

    @objc private func setThemeFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String, let theme = AeroControlTheme.named(id) else { return }
        onSelectTheme(theme)
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
