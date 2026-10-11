import AppKit
import AeroControlKit
import Common

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let onSettingsChanged: () -> Void
    private let bridge: NativeApiBridge
    let menu = NSMenu()

    init(onSettingsChanged: @escaping () -> Void, bridge: NativeApiBridge) {
        self.onSettingsChanged = onSettingsChanged
        self.bridge = bridge
        super.init()
        menu.delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(versionHeader())
        menu.addItem(sectionHeader("Compatible with AeroSpace ≥ 0.21.0"))
        menu.addItem(.separator())
        menu.addItem(keys())
        let theme = NSMenuItem(title: "Theme: \(AeroControlTheme.chosen.name)", action: nil, keyEquivalent: ""), themes = NSMenu()
        theme.image = swatch(for: AeroControlTheme.chosen)
        for t in AeroControlTheme.all {
            let entry = item(t.name) { AeroControlTheme.chosen = t; self.onSettingsChanged() }
            (entry.state, entry.image) = (AeroControlTheme.chosen == t ? .on : .off, swatch(for: t))
            themes.addItem(entry)
        }
        theme.submenu = themes
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
        menu.addItem(item("Quit AeroControl") { NSApp.terminate(nil) })
    }

    private func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = Action(run)
        return item
    }

    private func keys() -> NSMenuItem {
        let parent = NSMenuItem(title: "Keys", action: nil, keyEquivalent: ""), submenu = NSMenu()
        submenu.autoenablesItems = false
        submenu.items = [sectionHeader("On the map")] + KeyHelp.map.map(keyLine) + [.separator(), sectionHeader("In the strip")] + KeyHelp.strip.map(keyLine)
        parent.submenu = submenu
        return parent
    }

    private static let column: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: 190)]
        return style
    }()

    private func keyLine(_ row: KeyHelp.Row) -> NSMenuItem {
        let line = NSMenuItem(title: row.keys, action: nil, keyEquivalent: "")
        line.attributedTitle = NSAttributedString(string: "\(row.keys)\t\(row.does)", attributes: [.paragraphStyle: Self.column, .font: NSFont.menuFont(ofSize: 0)])
        return line
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

    private func swatch(for theme: AeroControlTheme) -> NSImage {
        let side: CGFloat = 12
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let palette = AeroControlPalette.of(theme, in: .dark)
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

extension AeroControlTheme {
    static var chosen: AeroControlTheme {
        get { UserDefaults.standard.string(forKey: "settings.theme").flatMap(named) ?? .system }
        set { UserDefaults.standard.set(newValue.id, forKey: "settings.theme") }
    }
}
