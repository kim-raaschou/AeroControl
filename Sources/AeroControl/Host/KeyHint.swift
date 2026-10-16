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

    var title: String {
        let words = rawValue.map { $0.isUppercase ? " " + $0.lowercased() : String($0) }.joined()
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    func frame(_ size: CGSize, in area: CGRect, margin: CGFloat) -> CGRect {
        let index = Self.allCases.firstIndex(of: self)!, room = area.insetBy(dx: margin, dy: margin)
        let (x, y) = ([0, 0.5, 1][index % 3], index < 3 ? 1.0 : 0)
        return CGRect(origin: CGPoint(x: room.minX + (room.width - size.width) * x, y: room.minY + (room.height - size.height) * y), size: size)
    }
}

private final class HintPanel: NSPanel {
    var onKey: ((FilterKey) -> Void)?

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let key = FilterKey(event: event) else { return super.keyDown(with: event) }
        onKey?(key)
    }
}

@MainActor
final class KeyHint {
    private let runner: AerospaceProcessRunner
    private let panel = HintPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let view = InteractiveHostingView(rootView: KeyHintView())
    private var pick = HintPick()
    private var mode = "main", pinned = false
    private var showing: Task<Void, Never>?

    static var delay: Int {
        get { UserDefaults.standard.object(forKey: "settings.keyHintDelay") as? Int ?? 400 }
        set { UserDefaults.standard.set(newValue, forKey: "settings.keyHintDelay") }
    }

    init(runner: AerospaceProcessRunner) {
        self.runner = runner
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        (panel.isOpaque, panel.backgroundColor, panel.hasShadow, panel.acceptsMouseMovedEvents) = (false, .clear, true, true)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = view
        panel.onKey = { [weak self] in self?.pressed($0) }
    }

    private var wanted: Bool { pinned || (KeyHintPlace.chosen != nil && mode != "main") }
    private var holdsKeys: Bool { pinned && pick.takesKeys }

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
            let mode = mode, rows = await wanted ? loadBindings(using: runner).filter { $0.mode == mode } : []
            guard !Task.isCancelled else { return }
            pick = pick.reloaded(rows, ringed: pinned && HintPick(rows).takesKeys)
            rows.isEmpty ? panel.orderOut(nil) : draw()
        }
    }

    private func pressed(_ key: FilterKey) {
        switch pick.key(key) {
        case .marked(let new): pick = new; draw()
        case .picked(let binding): trigger(binding)
        case .closed: toggle()
        case .nothing: break
        }
    }

    private func mark(_ keys: String?) {
        let new = pick.marking(keys ?? (holdsKeys ? pick.marked : nil))
        guard new != pick else { return }
        pick = new
        draw()
    }

    private func trigger(_ binding: KeyBinding) {
        pinned = false
        Task { [runner] in _ = try? await runner.run(AerospaceCommand.triggerBinding(binding)) }
        refresh()
    }

    private func draw() {
        view.rootView = KeyHintView(mode: mode, pick: pick, theme: AeroControlTheme.chosen, mark: { [weak self] in self?.mark($0) }, trigger: { [weak self] in self?.trigger($0) })
        panel.appearance = AeroControlTheme.chosen.isDark.flatMap { NSAppearance(named: $0 ? .darkAqua : .aqua) }
        panel.setFrame((KeyHintPlace.chosen ?? .bottom).frame(view.fittingSize, in: NSScreen.underMouse.visibleFrame, margin: 12), display: true)
        panel.invalidateShadow()
        if panel.isKeyWindow, !holdsKeys { panel.orderOut(nil) }
        holdsKeys ? panel.makeKeyAndOrderFront(nil) : panel.orderFrontRegardless()
    }
}

private struct KeyHintView: View {
    var mode = "", pick = HintPick(), theme = AeroControlTheme.chosen
    var mark: (String?) -> Void = { _ in }, trigger: (KeyBinding) -> Void = { _ in }
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("mode").font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                Text(mode).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(AeroControlPalette.of(theme, in: scheme).accent)
            }
            .padding(.horizontal, 4)
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(stride(from: 0, to: pick.bindings.count, by: pick.perColumn)), id: \.self) { start in
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(pick.bindings[start..<min(start + pick.perColumn, pick.bindings.count)], id: \.keys) { row($0) }
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
            Text(binding.chord).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(minWidth: 84, alignment: .leading)
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
        .padding(.horizontal, 4)
        .background(pick.marked == binding.keys ? AeroControlPalette.of(theme, in: scheme).accent.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .contentShape(Rectangle())
        .onHover { mark($0 ? binding.keys : nil) }
        .onTapGesture { trigger(binding) }
    }
}
