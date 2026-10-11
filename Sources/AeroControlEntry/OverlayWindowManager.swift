import AeroControlKit
import AppKit
import Common

@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    private var window: OverviewWindow?
    private static let revealAfter: Duration = .milliseconds(120)
    init(state: OverviewStore, settings: SettingsStore) {
        self.state = state
        self.settings = settings
        state.onEffect = { [weak self] in self?.perform($0) }
    }

    private func perform(_ effect: Visit.Host) {
        switch effect {
        case .show(let summon): show(summon)
        case .hide: hide()
        case .activate(let bundleId): app(bundleId)?.activate()
        case .quit(let bundleId): app(bundleId)?.terminate()
        case .launch(let ref): launch(ref)
        case .rebuild: rebuild()
        case .capture: if let window { Task { await state.capturePreviews(backingScale: window.targetScreen.backingScaleFactor) } }
        }
    }

    private func hide() {
        let ended: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, !self.state.visit.visible else { return }
            self.window?.contentView = nil
            self.window = nil
            self.state.endVisit()
        }
        if let window { window.dismiss(then: ended) } else { ended() }
    }

    private func app(_ bundleId: String) -> NSRunningApplication? {
        guard bundleId != Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    private func show(_ summon: Summon) {
        Task { [weak self] in
            guard let self, await self.state.open(summon) else { return }
            let window = self.replaceWindow()
            Task { [weak self] in
                try? await Task.sleep(for: Self.revealAfter)
                guard let self, self.state.visit.visible, self.window === window else { return }
                window.reveal()
            }
            await self.state.capturePreviews(backingScale: window.targetScreen.backingScaleFactor)
        }
    }

    private func targetScreen() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    func rebuild() {
        guard state.visit.visible else { return }
        replaceWindow().reveal()
    }

    private func replaceWindow() -> OverviewWindow {
        window?.contentView = nil
        window?.orderOut(nil)
        let window = makeWindow(for: targetScreen())
        self.window = window
        return window
    }

    private func launch(_ ref: AppRef) {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        switch ref {
        case .bundleId(let id): open.arguments = ["-b", id]
        case .name(let name): open.arguments = ["-a", name]
        }
        open.terminationHandler = { process in
            guard process.terminationStatus != 0 else { return }
            Task { @MainActor [weak self] in self?.state.update { $0.launchFailed(ref) } }
        }
        try? open.run()
    }

    private func makeWindow(for screen: NSScreen) -> OverviewWindow {
        let window = OverviewWindow(targetScreen: screen)
        window.appearance = settings.theme.isDark.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? nil
        let screenFrames = Dictionary(uniqueKeysWithValues: NSScreen.screens.enumerated().map { index, screen in
            let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let visible = screen.visibleFrame
            return (index + 1, CGRect(x: visible.minX, y: top - visible.maxY, width: visible.width, height: visible.height))
        })
        let motion: Double = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1
        window.motion = motion
        window.onKey = { [weak self] in self?.state.handle($0) ?? false }
        state.screen = (screen.frame.size, screenFrames)
        let root = OverviewRoot(state: state, theme: settings.theme, motion: motion)
        let hostingView = InteractiveHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        return window
    }
}
