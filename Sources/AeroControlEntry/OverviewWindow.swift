import AppKit
import AeroControlKit
import OSLog
import SwiftUI

private let log = Logger(subsystem: "com.aerocontrol.AeroControl", category: "overview")

final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }
}

/// Mission-Control-style presentation: one borderless panel covering the whole screen,
/// with a blurred, dimmed backdrop and the workspace cards centered on it. Escape or a
/// click on the backdrop dismisses; the app stays an accessory (non-activating panel).
class OverviewWindow: NSPanel {
    private static let fadeDuration: TimeInterval = 0.2
    private let targetScreen: NSScreen
    var onDismiss: (() -> Void)?
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

    override func cancelOperation(_ sender: Any?) {
        log.debug("overview: cancelOperation")
        onDismiss?()
    }

    override func keyDown(with event: NSEvent) {
        log.debug("overview: keyDown \(event.keyCode)")
        if event.keyCode == 53 { onDismiss?() } else { super.keyDown(with: event) }
    }

    /// While the overview is up it owns the keyboard: if another app takes key status
    /// (activation shuffles after the summon), take it back so Escape keeps working.
    override func resignKey() {
        super.resignKey()
        guard isVisible, !isDismissing else { return }
        log.notice("overview: lost key status while visible; retaking")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isDismissing else { return }
            self.makeKey()
        }
    }

    func installContent(hosting: NSView) {
        contentView = hosting
        setFrame(targetScreen.frame, display: false)
    }

    func reveal() {
        isDismissing = false
        setFrame(targetScreen.frame, display: true)
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        log.notice("overview: revealed, isKeyWindow=\(self.isKeyWindow), appActive=\(NSApp.isActive)")
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        guard isVisible else { return }
        isDismissing = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.orderOut(nil)
                self.alphaValue = 1
            }
        }
    }
}

/// The full-screen root: blurred backdrop (click to dismiss) with the panel centered.
struct OverviewRoot: View {
    let panel: AeroControlPanel
    let theme: AeroControlTheme
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            BackdropBlur()
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
            theme.palette(for: colorScheme).backdrop
                .ignoresSafeArea()
                .allowsHitTesting(false)
            panel
        }
        .environment(\.aeroTheme, theme)
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
