import AeroControlKit
import AppKit
import Common

@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let bridge: NativeApiBridge
    private let settings: SettingsStore

    private var window: OverviewWindow?
    private static let revealAfter: Duration = .milliseconds(120)
    init(state: OverviewStore, bridge: NativeApiBridge, settings: SettingsStore) {
        self.state = state
        self.bridge = bridge
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
        case .capture: if let screen = window?.targetScreen { Task { await capture(on: screen) } }
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
        state.endVisit()
        Task { [weak self] in
            guard let self else { return }
            self.bridge.prepareCapture()
            await self.state.reload()
            self.state.update { $0.summoned(summon) }
            guard self.state.visit.visible else { return }
            await self.state.measurePreviews()
            guard self.state.visit.visible else { return }
            self.state.following = true
            self.window?.contentView = nil
            self.window?.orderOut(nil)
            let screen = self.targetScreen()
            let window = self.makeWindow(for: screen, hidden: true)
            self.window = window
            Task { [weak self] in
                try? await Task.sleep(for: Self.revealAfter)
                guard let self, self.state.visit.visible, self.window === window else { return }
                window.reveal()
            }
            await self.capture(on: screen)
        }
    }

    private func capture(on screen: NSScreen) async {
        await state.capturePreviews(maxSize: AeroControlLayout.captureSize(available: screen.frame.size, backingScale: screen.backingScaleFactor,
                                                                           workspaces: state.model.workspaces.count, strip: state.strip != nil))
    }

    private func targetScreen() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    func rebuild() {
        guard state.visit.visible else { return }
        window?.contentView = nil
        window?.orderOut(nil)
        window = makeWindow(for: targetScreen(), hidden: false)
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

    private func makeWindow(for screen: NSScreen, hidden: Bool) -> OverviewWindow {
        let window = OverviewWindow(targetScreen: screen)
        window.appearance = settings.theme.isDark.map { NSAppearance(named: $0 ? .darkAqua : .aqua) } ?? nil
        let screenFrames = Dictionary(uniqueKeysWithValues: NSScreen.screens.enumerated().map { index, screen in
            let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let visible = screen.visibleFrame
            return (index + 1, CGRect(x: visible.minX, y: top - visible.maxY, width: visible.width, height: visible.height))
        })
        let motion: Double = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 1
        window.motion = motion
        window.onDismiss = { [weak self] in self?.state.update { $0.hide(restoreFocus: true) } }
        window.onQuitApp = { [weak self] in self?.state.update { $0.quitRinged() } }
        window.onCloseWindow = { [weak self] in self?.state.update { $0.closeRinged() } }
        window.onKey = { [weak self] in self?.state.handle($0) ?? false }
        state.screen = (screen.frame.size, screenFrames)
        let root = OverviewRoot(
            state: state,
            panel: AeroControlPanel(state: state),
            theme: settings.theme,
            motion: motion,
            onDismiss: { [weak self] in self?.state.update { $0.hide(restoreFocus: true) } }
        )
        let hostingView = InteractiveHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        if !hidden { window.reveal() }
        return window
    }
}
