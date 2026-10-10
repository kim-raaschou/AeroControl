import AppKit
import AeroControlKit
import Common
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.aerocontrol.AeroControl", category: "overview")

final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }
}

/// Mission-Control-style presentation: one borderless panel covering the whole screen, with a
/// blurred, dimmed backdrop and the workspace cards centered on it.
class OverviewWindow: NSPanel {
    private static let fadeDuration: TimeInterval = 0.2
    /// The animation scale from settings; 0 reveals and dismisses in one frame.
    var motion: Double = 1
    private var fade: TimeInterval { Self.fadeDuration * motion }
    private let targetScreen: NSScreen
    var onDismiss: (() -> Void)?
    /// ⌘Q and ⌘W: quit the app, close the window, under the ring (`OverlayWindowManager`).
    var onQuitApp: (() -> Void)?
    var onCloseWindow: (() -> Void)?
    /// Offers a keystroke to the type-to-filter host; true when it took it.
    var onKey: ((FilterKey) -> Bool)?
    private var isDismissing = false

    init(targetScreen: NSScreen) {
        self.targetScreen = targetScreen
        super.init(
            contentRect: targetScreen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    /// Key so Escape reaches us; non-activating so the app never takes over the menu bar.
    override var canBecomeKey: Bool { true }

    /// Escape also arrives here rather than through `keyDown` — Cmd-period always does — so the
    /// filter gets the same first refusal it gets there.
    override func cancelOperation(_ sender: Any?) {
        log.debug("overview: cancelOperation")
        if onKey?(.escape) == true { return }
        onDismiss?()
    }

    /// ⌘W closes the window under the ring and ⌘Q quits its app, on the map and in the strip, as
    /// they would without the overview, which stays up so you see each go.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // Only the modifiers that mean something here; the flags also carry `.numericPad` and `.function`.
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.subtracting(.shift) == .command else { return super.performKeyEquivalent(with: event) }
        if let key = FilterKey(command: key, shift: modifiers.contains(.shift)), onKey?(key) == true { return true }
        // Every other ⌘ key is nothing: passed on, the app's menu could act on AeroControl
        // (⌘H, Hide) under an overview that still holds itself as shown. ⇧⌘Q names a workspace.
        switch (key, modifiers.contains(.shift)) {
        case ("q", false): onQuitApp?()
        case ("w", false): onCloseWindow?()
        default: break
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        log.debug("overview: keyDown \(event.keyCode)")
        if let key = FilterKey(event: event), onKey?(key) == true { return }
        if event.keyCode == 53 { onDismiss?() } else { super.keyDown(with: event) }
    }

    /// While the overview is up it owns the keyboard: if another app takes key status (activation
    /// shuffles after the summon), take it back so Escape keeps working.
    override func resignKey() {
        super.resignKey()
        guard isVisible, !isDismissing else { return }
        log.notice("overview: lost key status while visible; retaking")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isDismissing else { return }
            self.makeKey()
        }
    }

    func reveal() {
        isDismissing = false
        setFrame(targetScreen.frame, display: true)
        alphaValue = 1                      // at once: see `OverviewRoot`
        makeKeyAndOrderFront(nil)
        log.notice("overview: revealed, isKeyWindow=\(self.isKeyWindow), appActive=\(NSApp.isActive)")
    }

    /// Fades out, then `gone`: what is drawn stays as it was until it is off the screen.
    func dismiss(then gone: @escaping @MainActor @Sendable () -> Void) {
        guard isVisible else { return gone() }
        isDismissing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = fade
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return gone() }
                self.orderOut(nil)
                self.alphaValue = 1
                gone()
            }
        }
    }
}

/// AppKit's half of `FilterKey`, which lives in `Common` and may not see an `NSEvent`.
private extension FilterKey {
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        self.init(keyCode: event.keyCode, characters: event.characters)
    }
}

/// The full-screen root: blurred backdrop (click to dismiss) with the panel centered.
struct OverviewRoot: View {
    let state: OverviewStore
    let panel: AeroControlPanel
    let theme: AeroControlTheme
    let motion: Double
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// The overview comes in at once; only its pictures fade in.

    var body: some View {
        let palette = theme.palette(for: colorScheme)
        ZStack {
            ZStack {
                BackdropBlur()
                palette.backdrop
            }
            // The strip floats over the desktop, the map dims it; 0.002, not 0, so a click still lands here.
            .opacity(state.strip != nil || state.missingApp != nil ? 0.002 : 1)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture(perform: onDismiss)
            panel
        }
        .environment(\.aeroLook, AeroLook(palette: palette, motion: motion))
    }
}

private struct BackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .fullScreenUI
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
