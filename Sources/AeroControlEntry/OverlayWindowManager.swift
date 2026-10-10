import AeroControlKit
import AppKit
import Common

@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let bridge: NativeApiBridge
    private let settings: SettingsStore

    private var window: OverviewWindow?
    private var requestedVisible = false
    private var loading = false
    private static let revealAfter: Duration = .milliseconds(120)
    init(state: OverviewStore, bridge: NativeApiBridge, settings: SettingsStore) {
        self.state = state
        self.bridge = bridge
        self.settings = settings
        state.onShotDone = { [weak self] in self?.hide(restoreFocus: $0) }
    }

    private func hide(restoreFocus: Bool) {
        guard requestedVisible else { return }
        requestedVisible = false
        let ended: @MainActor @Sendable () -> Void = { [weak self] in
            guard let self, !self.requestedVisible else { return }
            self.window?.contentView = nil
            self.window = nil
            self.state.endVisit()
        }
        if let window { window.dismiss(then: ended) } else { ended() }
        guard restoreFocus, let app = owner(ofWindow: state.model.focusedWindowId) else { return }
        app.activate()
    }

    private func owner(ofWindow windowId: Int) -> NSRunningApplication? {
        let window = state.model.workspaces.flatMap(\.windows).first { $0.windowId == windowId }
        guard let bundleId = window?.bundleId, bundleId != Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    private func quitRingedApp() {
        guard requestedVisible, let target = state.commandTarget, let app = owner(ofWindow: target.windowId) else { return }
        app.terminate()
    }

    private func closeRingedWindow() {
        guard let target = state.commandTarget else { return }
        state.send(.action(.closeWindow(target.windowId)))
    }

    private func handleKey(_ key: FilterKey) -> Bool {
        guard requestedVisible else { return false }
        let action = state.handle(key)
        if case .focus(let windowId) = action { state.send(.action(.focusWindow(windowId))) }
        return action != .none
    }

    private func show(_ summon: Summon) {
        state.endVisit()
        requestedVisible = true
        loading = true
        Task { [weak self] in
            guard let self else { return }
            self.bridge.prepareCapture()
            await self.state.reload()
            self.loading = false
            guard self.requestedVisible else { return }
            switch summon {
            case .map: break
            case .app(let ref): guard self.carryOut(self.state.summonApp(ref)) else { return }
            }
            if self.bridge.canCapturePreviews {
                await self.state.measurePreviews()
                guard self.requestedVisible else { return }
            } else {
                self.bridge.requestPreviewAccess()
            }
            self.state.following = true
            self.window?.contentView = nil
            self.window?.orderOut(nil)
            let screen = self.targetScreen()
            let window = self.makeWindow(for: screen, hidden: true)
            self.window = window
            Task { [weak self] in
                if self?.bridge.canCapturePreviews == true { try? await Task.sleep(for: Self.revealAfter) }
                guard let self, self.requestedVisible, self.window === window else { return }
                window.reveal()
            }
            await self.state.capturePreviews(maxSize: AeroControlLayout.captureSize(available: screen.frame.size, backingScale: screen.backingScaleFactor,
                                                                                     workspaces: self.state.model.workspaces.count, strip: self.state.strip != nil))
        }
    }

    private func carryOut(_ action: AppSummon) -> Bool {
        switch action {
        case .pick:
            return true
        case .focus(let windowId):
            state.send(.action(.focusWindow(windowId)))
        case .launch(let ref):
            hide(restoreFocus: false)
            launch(ref)
        }
        return false
    }

    private func targetScreen() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    func rebuild() {
        guard requestedVisible else { return }
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
            Task { @MainActor [weak self] in
                guard let self, !self.requestedVisible else { return }
                self.requestedVisible = true
                self.state.missingApp = ref
                self.rebuild()
            }
        }
        try? open.run()
    }

    func toggleVisibility(_ summon: Summon = .map) {
        guard requestedVisible else { return show(summon) }
        guard !loading else { return }
        switch summon.again(stripApp: state.strip?.app, among: state.model.workspaces.flatMap(\.windows)) {
        case .close: hide(restoreFocus: true)
        case .step: _ = state.handle(.move(.window(1)))
        case .summon(let ref): _ = carryOut(state.summonApp(ref))
        }
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
        window.onDismiss = { [weak self] in self?.hide(restoreFocus: true) }
        window.onQuitApp = { [weak self] in self?.quitRingedApp() }
        window.onCloseWindow = { [weak self] in self?.closeRingedWindow() }
        window.onKey = { [weak self] in self?.handleKey($0) ?? false }
        state.screen = (screen.frame.size, screenFrames)
        let root = OverviewRoot(
            state: state,
            panel: AeroControlPanel(state: state),
            theme: settings.theme,
            motion: motion,
            onDismiss: { [weak self] in self?.hide(restoreFocus: true) }
        )
        let hostingView = InteractiveHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.contentView = hostingView
        if !hidden { window.reveal() }
        return window
    }
}
