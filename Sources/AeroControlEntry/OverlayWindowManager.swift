import AeroControlKit
import AppKit
import Common

@MainActor
final class OverlayWindowManager {
    private let state: OverviewStore
    private let settings: SettingsStore

    /// The overview is one window on one screen: the one under the mouse at summon time,
    /// like Mission Control. It always lists every workspace, whichever monitor it lives on.
    private var window: OverviewWindow?
    /// One-shot overview: starts hidden, summoned by the toggle.
    private var requestedVisible = false
    /// Previews are captured to fit this box (points); tiles are drawn at 3:2 of the icon size.
    private static let previewCaptureSize = CGSize(width: 720, height: 480)

    init(
        state: OverviewStore,
        settings: SettingsStore
    ) {
        self.state = state
        self.settings = settings
    }

    private func makePanel(availableSize: NSSize) -> AeroControlPanel {
        AeroControlPanel(
            state: state,
            availableWidth: availableSize.width,
            availableHeight: availableSize.height,
            onDismiss: { [weak self] in self?.hide(restoreFocus: false) }   // the action focused something
        )
    }

    /// Escape and the backdrop dismiss without choosing anything; then the keyboard goes
    /// back to the app that owns the focused window, since summoning leaves AeroControl
    /// as the frontmost app. AeroSpace cannot do this for us: the window is already its
    /// focused one, so `focus` is a no-op there.
    private func hide(restoreFocus: Bool) {
        guard requestedVisible else { return }
        requestedVisible = false
        state.clearPreviews()
        window?.dismiss()
        guard restoreFocus, let owner = focusedWindowOwner() else { return }
        owner.activate()
    }

    private func focusedWindowOwner() -> NSRunningApplication? {
        let focused = state.model.focusedWindowId
        let window = state.model.workspaces.flatMap(\.windows).first { $0.windowId == focused }
        guard let bundleId = window?.bundleId else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first
    }

    /// The window is rebuilt per summon; a SwiftUI hosting view is cheap and this keeps
    /// display changes and settings changes free of special cases.
    private func show() {
        requestedVisible = true
        guard state.previewsAvailable else {
            // Ask macOS for Screen Recording on the first summon without it. The system
            // shows its dialog once per app; afterwards this is a silent no-op and the
            // menu item / System Settings is the way in. Icons are shown meanwhile.
            state.requestPreviewAccess()
            rebuild()
            return
        }
        // Nothing is shown until the snapshots are in: one fade-in with the images in
        // place instead of icons that get replaced a moment later.
        Task { [weak self] in
            guard let self else { return }
            await self.state.capturePreviews(maxSize: Self.previewCaptureSize)
            guard self.requestedVisible else { return }   // toggled away while capturing
            self.rebuild()
        }
    }

    private func targetScreen() -> NSScreen {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
            ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
    }

    func rebuild() {
        window?.orderOut(nil)
        window = makeWindow(for: targetScreen(), hidden: !requestedVisible)
    }

    func showErrorFallbackIfNeeded() {
        guard state.error != nil, window == nil else { return }
        requestedVisible = true          // so Escape and the backdrop can dismiss it again
        window = makeWindow(for: targetScreen(), hidden: false)
    }

    func removeAll() {
        window?.dismiss()
        window = nil
    }

    func toggleVisibility() {
        if requestedVisible { hide(restoreFocus: true) } else { show() }
    }

    func selectTheme(_ theme: AeroControlTheme) {
        settings.setTheme(theme)
        rebuild()
    }

    private func makeWindow(for screen: NSScreen, hidden: Bool) -> OverviewWindow {
        let window = OverviewWindow(targetScreen: screen)
        window.onDismiss = { [weak self] in self?.hide(restoreFocus: true) }
        let root = OverviewRoot(
            panel: makePanel(availableSize: screen.frame.size),
            theme: settings.theme,
            onDismiss: { [weak self] in self?.hide(restoreFocus: true) }
        )
        let hostingView = InteractiveHostingView(rootView: root)
        hostingView.sizingOptions = []
        window.installContent(hosting: hostingView)
        if !hidden { window.reveal() }
        return window
    }
}
