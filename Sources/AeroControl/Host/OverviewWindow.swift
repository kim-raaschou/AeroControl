import AppKit
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
    let targetScreen: NSScreen
    var onKey: ((FilterKey) -> Void)?
    var onLend: (() -> Void)?
    private var isDismissing = false
    private var lending = false

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
        onKey?(.escape)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool { event.modifierFlags.contains(.command) || super.performKeyEquivalent(with: event) }

    override func flagsChanged(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard [54, 55].contains(event.keyCode), flags.contains(.command), flags.isDisjoint(with: [.control, .option]) else { return }
        lend()
    }

    private func lend() {
        onLend?()
        lending = true
        NSApp.deactivate()
        Task { @MainActor [weak self] in
            while NSEvent.modifierFlags.contains(.command) { try? await Task.sleep(for: .milliseconds(30)) }
            guard let self else { return }
            self.lending = false
            if self.isVisible, !self.isDismissing { self.makeKey() }
        }
    }

    override func keyDown(with event: NSEvent) {
        log.debug("overview: keyDown \(event.keyCode)")
        guard let key = FilterKey(event: event) else { return super.keyDown(with: event) }
        onKey?(key)
    }

    override func resignKey() {
        super.resignKey()
        guard isVisible, !isDismissing, !lending else { return }
        log.notice("overview: lost key status while visible; retaking")
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isVisible, !self.isDismissing, !self.lending else { return }
            self.makeKey()
        }
    }

    func reveal() {
        setFrame(targetScreen.frame, display: true)
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
                gone()
            }
        }
    }
}

extension FilterKey {
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        self.init(keyCode: event.keyCode, characters: event.characters)
    }
}

struct OverviewRoot: View {
    let state: OverviewStore
    let motion: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let palette = AeroControlPalette.system(colorScheme)
        ZStack {
            palette.backdrop
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { state.update { $0.cancel() } }
            AeroControlPanel(state: state)
        }
        .environment(\.aeroLook, AeroLook(palette: palette, motion: motion))
    }
}
