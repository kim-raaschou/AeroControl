import AppKit
import Common
import SwiftUI
import UniformTypeIdentifiers

enum KeyHintPlace: String, CaseIterable {
    case topLeft, top, topRight, bottomLeft, bottom, bottomRight

    static var chosen: KeyHintPlace? {
        get { KeyHintPlace(rawValue: UserDefaults.standard.string(forKey: "settings.keyHint") ?? "bottom") }
        set { UserDefaults.standard.set(newValue?.rawValue ?? "off", forKey: "settings.keyHint") }
    }

    func frame(_ size: CGSize, in area: CGRect, margin: CGFloat) -> CGRect {
        let index = Self.allCases.firstIndex(of: self)!, room = area.insetBy(dx: margin, dy: margin)
        let (x, y) = ([0, 0.5, 1][index % 3], index < 3 ? 1.0 : 0)
        return CGRect(origin: CGPoint(x: room.minX + (room.width - size.width) * x, y: room.minY + (room.height - size.height) * y), size: size)
    }
}

@MainActor
final class KeyHint {
    private let runner: AerospaceProcessRunner
    private let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private var bindings: [KeyBinding] = []
    private var mode = "main", pinned = false
    private var showing: Task<Void, Never>?

    static var delay: Int {
        get { UserDefaults.standard.object(forKey: "settings.keyHintDelay") as? Int ?? 400 }
        set { UserDefaults.standard.set(newValue, forKey: "settings.keyHintDelay") }
    }

    init(runner: AerospaceProcessRunner) {
        self.runner = runner
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        (panel.isOpaque, panel.backgroundColor, panel.hasShadow, panel.ignoresMouseEvents) = (false, .clear, true, true)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    private var wanted: Bool { pinned || (KeyHintPlace.chosen != nil && mode != "main") }

    func toggle() { pinned.toggle(); refresh() }

    func heard(_ event: AerospaceEvent) {
        guard case .mode(let mode) = event else { return }
        self.mode = mode
        refresh(after: .milliseconds(mode == "main" ? 0 : Self.delay))
    }

    func refresh(after delay: Duration = .zero) {
        showing?.cancel()
        showing = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            bindings = await wanted ? loadBindings(using: runner) : []
            bindings.contains { $0.mode == mode } ? draw() : panel.orderOut(nil)
        }
    }

    private func draw() {
        let view = NSHostingView(rootView: KeyHintView(mode: mode, bindings: bindings.filter { $0.mode == mode }, theme: AeroControlTheme.chosen))
        panel.appearance = AeroControlTheme.chosen.isDark.flatMap { NSAppearance(named: $0 ? .darkAqua : .aqua) }
        panel.contentView = view
        panel.setFrame((KeyHintPlace.chosen ?? .bottom).frame(view.fittingSize, in: NSScreen.underMouse.visibleFrame, margin: 12), display: true)
        panel.invalidateShadow()
        panel.orderFrontRegardless()
    }
}

private struct KeyHintView: View {
    let mode: String
    let bindings: [KeyBinding]
    let theme: AeroControlTheme
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let columns = max(1, (bindings.count + 11) / 12), perColumn = (bindings.count + columns - 1) / columns
        return VStack(alignment: .leading, spacing: 6) {
            Text(mode).font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(AeroControlPalette.of(theme, in: scheme).accent)
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(stride(from: 0, to: bindings.count, by: perColumn)), id: \.self) { start in
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(bindings[start..<min(start + perColumn, bindings.count)], id: \.keys) { row($0) }
                    }
                }
            }
        }
        .padding(10)
        .fixedSize()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ binding: KeyBinding) -> some View {
        HStack(spacing: 8) {
            Text(binding.chord).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(minWidth: 64, alignment: .leading)
            if let id = binding.app {
                let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
                Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable().frame(width: 14, height: 14)
                Text(url?.deletingPathExtension().lastPathComponent ?? id)
            } else {
                Text(binding.does.isEmpty ? "—" : binding.does).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(.vertical, 1)
    }
}

final class KeyHintPicker: NSView {
    private let changed: () -> Void

    init(changed: @escaping () -> Void) {
        self.changed = changed
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 92))
    }

    required init?(coder: NSCoder) { nil }

    private var screen: NSRect { bounds.insetBy(dx: 40, dy: 8) }

    private func spot(_ place: KeyHintPlace) -> NSRect {
        place.frame(CGSize(width: 26, height: 10), in: screen.insetBy(dx: 0, dy: 3).offsetBy(dx: 0, dy: -3), margin: 6)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.secondaryLabelColor.set()
        let outline = NSBezierPath(roundedRect: screen, xRadius: 6, yRadius: 6)
        outline.lineWidth = 1.5
        outline.stroke()
        NSRect(x: screen.minX, y: screen.maxY - 6, width: screen.width, height: 1).fill()
        for place in KeyHintPlace.allCases {
            let mark = NSBezierPath(roundedRect: spot(place), xRadius: 3, yRadius: 3)
            if place == KeyHintPlace.chosen { NSColor.controlAccentColor.setFill(); mark.fill() } else { NSColor.tertiaryLabelColor.setStroke(); mark.stroke() }
        }
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let place = KeyHintPlace.allCases.first(where: { spot($0).insetBy(dx: -6, dy: -6).contains(point) }) else { return }
        KeyHintPlace.chosen = place == KeyHintPlace.chosen ? nil : place
        needsDisplay = true
        changed()
    }
}
