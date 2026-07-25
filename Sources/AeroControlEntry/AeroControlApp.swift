import SwiftUI
import AppKit
import Common
import AeroControlKit

@main
struct AeroControlApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: OverviewStore!
    private var overlayManager: OverlayWindowManager!
    private var menuBarController: MenuBarController!
    private var settings: SettingsStore!
    private let instanceGuard = SingleInstanceGuard()
    private var statusItem: NSStatusItem?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var fullscreenRefreshTimer: DispatchSourceTimer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let lockName = "com.aerocontrol.single-instance.lock"
        guard instanceGuard.tryAcquire(name: lockName) else {
            if let pid = instanceGuard.runningInstancePID(name: lockName) {
                kill(pid, SIGUSR1)
            }
            exit(0)
        }

        signal(SIGUSR1, SIG_IGN)

        NSApp.setActivationPolicy(.accessory)

        let runner = AerospaceSocketRunner()
        let nativeSystem = NativeApiBridgeAdapter()

        state = OverviewStore(runner: runner, nativeSystem: nativeSystem)

        settings = SettingsStore()

        menuBarController = MenuBarController(
            onQuit: { [weak self] in self?.quit() },
            onToggle: { [weak self] in self?.overlayManager.toggleVisibility() },
            onSelectEdge: { [weak self] edge in self?.overlayManager.selectEdge(edge) },
            onSelectScreen: { [weak self] screen in self?.overlayManager.selectScreen(screen) },
            onToggleMultiScreen: { [weak self] in self?.overlayManager.toggleMultiScreen() },
            onReset: { [weak self] in self?.overlayManager.rebuild() },
            settings: settings
        )

        overlayManager = OverlayWindowManager(
            state: state,
            settings: settings
        )
        overlayManager.activateInitialScreen()

        installStatusItem()
        installWorkspaceObservers()

        state.onMonitorsChanged = { [weak self] in self?.overlayManager.rebuild() }
        state.onLoaded = { [weak self] in self?.overlayManager.showErrorFallbackIfNeeded() }

        Task {
            await state.start()
        }

        NSApp.activate(ignoringOtherApps: true)

        menuBarController.install()
    }

    @MainActor private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(
                systemSymbolName: "square.grid.3x3.fill",
                accessibilityDescription: "AeroControl"
            )
            image?.isTemplate = true
            button.image = image
        }
        item.menu = menuBarController.settingsMenu()
        statusItem = item
    }

    @MainActor private func performTeardown() {
        fullscreenRefreshTimer?.cancel()
        fullscreenRefreshTimer = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        menuBarController?.teardown()
        state?.stop()
        overlayManager?.removeAll()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    @MainActor private func quit() {
        performTeardown()
        UserDefaults.standard.synchronize()
        exit(0)
    }

    func applicationWillTerminate(_ notification: Notification) {
        performTeardown()
    }

    @MainActor private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let onSpaceChange = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFullscreenVisibility() }
        }
        let onAppActivate = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshFullscreenVisibility() }
        }
        workspaceObservers = [onSpaceChange, onAppActivate]
        installFullscreenRefreshTimer()
    }

    @MainActor private func refreshFullscreenVisibility() {
        overlayManager.applyFullscreenVisibility()
    }

    @MainActor private func installFullscreenRefreshTimer() {
        fullscreenRefreshTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(300), repeating: .milliseconds(400))
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshFullscreenVisibility()
            }
        }
        timer.resume()
        fullscreenRefreshTimer = timer
    }
}
