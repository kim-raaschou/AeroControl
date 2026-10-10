import AppKit
import AeroControlKit
import Common

/// The menu under the status item. Every item carries what it does, so there is one handler;
/// the menu is rebuilt each time it opens, so it always shows the current settings.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    /// Any setting changed: the host redraws the overview with it.
    private let onSettingsChanged: () -> Void
    /// Show overview, show the focused app's strip: the host summons, as the keys do.
    private let onSummon: (Summon) -> Void
    /// The window AeroSpace has focused, read when an item about it is chosen.
    private let focusedWindow: () async -> WindowInfo?
    /// Screen Recording: whether macOS lets us take the pictures, and how to ask.
    private let bridge: NativeApiBridge
    private let settings: SettingsStore

    init(onSettingsChanged: @escaping () -> Void, onSummon: @escaping (Summon) -> Void,
         focusedWindow: @escaping () async -> WindowInfo?, bridge: NativeApiBridge, settings: SettingsStore) {
        self.onSettingsChanged = onSettingsChanged
        self.onSummon = onSummon
        self.focusedWindow = focusedWindow
        self.bridge = bridge
        self.settings = settings
    }

    /// Empty until it opens: `menuNeedsUpdate` fills it every time, the first included.
    func settingsMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
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
        menu.addItem(item("Show overview") { self.onSummon(.map) })
        menu.addItem(item("Show strip for the focused app") { self.withFocusedWindow { self.onSummon(.app(.bundleId($0.bundleId))) } })
        menu.addItem(.separator())
        // Submenus, not thirty items: each parent names the current choice, the theme with its swatch.
        let theme = choice("Theme", current: settings.theme.name, options: AeroControlTheme.all.map { t in
            (t.name, swatch(for: t), settings.theme == t, { self.settings.theme = t }) })
        theme.image = swatch(for: settings.theme)
        menu.addItem(theme)

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Window Previews"))
        if bridge.canCapturePreviews {
            menu.addItem(sectionHeader("On — Screen Recording granted"))
        } else {
            let grant = item("Enable window previews (Screen Recording)…") { self.bridge.requestPreviewAccess() }
            grant.toolTip = "Previews capture each window once when the overview opens. Without it the tiles stay empty plates."
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        // The key lines, to paste into your AeroSpace config: AeroControl writes no config.
        menu.addItem(item("Copy AeroSpace key for the map") { self.copy(aerospaceMapBinding) })
        menu.addItem(item("Copy AeroSpace key for the focused app") { self.withFocusedWindow { self.copy(aerospaceBinding(for: $0)) } })
        menu.addItem(.separator())
        menu.addItem(item("Quit AeroControl") { NSApp.terminate(nil) })
    }

    private func copy(_ line: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(line, forType: .string) }

    /// `run` with the window AeroSpace has focused; nothing with none.
    private func withFocusedWindow(_ run: @escaping (WindowInfo) -> Void) {
        Task { await self.focusedWindow().map(run) }
    }

    /// An item that does `run` when chosen.
    private func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Action(run)
        return item
    }

    /// A submenu of exclusive choices; the parent names the current one. Choosing one applies
    /// the setting and redraws the overview.
    private func choice(_ label: String, current: String,
                        options: [(name: String, image: NSImage?, isOn: Bool, select: () -> Void)]) -> NSMenuItem {
        let parent = NSMenuItem(title: "\(label): \(current)", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for option in options {
            let entry = item(option.name) { option.select(); self.onSettingsChanged() }
            entry.state = option.isOn ? .on : .off
            entry.image = option.image
            submenu.addItem(entry)
        }
        parent.submenu = submenu
        return parent
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
}
