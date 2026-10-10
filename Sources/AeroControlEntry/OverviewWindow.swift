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

class OverviewWindow: NSPanel {
    private static let fadeDuration: TimeInterval = 0.2
    var motion: Double = 1
    private var fade: TimeInterval { Self.fadeDuration * motion }
    private let targetScreen: NSScreen
    var onDismiss: (() -> Void)?
    var onQuitApp: (() -> Void)?
    var onCloseWindow: (() -> Void)?
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

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        log.debug("overview: cancelOperation")
        if onKey?(.escape) == true { return }
        onDismiss?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers ?? ""
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers.subtracting(.shift) == .command else { return super.performKeyEquivalent(with: event) }
        if let key = FilterKey(command: key, shift: modifiers.contains(.shift)), onKey?(key) == true { return true }
        switch (key.lowercased(), modifiers.contains(.shift)) {
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
        alphaValue = 1
        makeKeyAndOrderFront(nil)
        log.notice("overview: revealed, isKeyWindow=\(self.isKeyWindow), appActive=\(NSApp.isActive)")
    }

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

private extension FilterKey {
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        self.init(keyCode: event.keyCode, characters: event.characters)
    }
}

struct OverviewRoot: View {
    let state: OverviewStore
    let panel: AeroControlPanel
    let theme: AeroControlTheme
    let motion: Double
    let onDismiss: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AeroControlPalette.of(theme, in: colorScheme)
        ZStack {
            ZStack {
                BackdropBlur()
                palette.backdrop
            }
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
