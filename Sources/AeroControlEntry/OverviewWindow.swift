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

/// Mission-Control-style presentation: one borderless panel covering the whole screen,
/// with a blurred, dimmed backdrop and the workspace cards centered on it. Escape or a
/// click on the backdrop dismisses; the app stays an accessory (non-activating panel).
class OverviewWindow: NSPanel {
    private static let fadeDuration: TimeInterval = 0.2
    private let targetScreen: NSScreen
    var onDismiss: (() -> Void)?
    /// Cmd-Q: quit the app whose window the mouse is over, Mission-Control style.
    var onQuitPointedApp: (() -> Void)?
    /// Offers a keystroke to the type-to-filter host; true when it took it.
    var onKey: ((FilterKey) -> Bool)?
    /// Cmd-1…Cmd-9: focus the nth match; false when the filter has no nth match to give.
    var onSelectMatch: ((Int) -> Bool)?
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

    /// Escape also arrives here rather than through `keyDown` — Cmd-period always does — so
    /// the filter gets the same first refusal it gets there. Two Escape routes meaning two
    /// different things is how Escape came to skip clearing the query on one of them.
    override func cancelOperation(_ sender: Any?) {
        log.debug("overview: cancelOperation")
        if onKey?(.escape) == true { return }
        onDismiss?()
    }

    /// Cmd-Q quits the app the mouse is over and leaves the overview up, so several can
    /// go in one visit — Mission Control's behaviour. Cmd-W just leaves.
    ///
    /// Both have to be intercepted here because summoning activates AeroControl, so while
    /// the overview is up it owns the menu bar, including the Quit item SwiftUI installs by
    /// default. Left alone, a stray Cmd-Q killed the whole agent: the overlay vanished, the
    /// app underneath came to the front, and the summon keybind silently did nothing until
    /// AeroControl was launched again. Quit stays in the menu bar item.
    ///
    /// Cmd-1…Cmd-9 picks the nth match — the Alfred/Raycast idiom — and belongs here for the
    /// opposite reason: a plain digit is text the user is typing, and must never be taken
    /// from the query.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        // Only the modifiers that mean something here: a digit key reports `.numericPad`
        // even on the top row, so comparing the whole flag set against `.command` silently
        // excluded Cmd-1…Cmd-9 while Cmd-Q and Cmd-W worked.
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        guard modifiers == .command else { return super.performKeyEquivalent(with: event) }
        switch key {
        case "q": onQuitPointedApp?()
        case "w": onDismiss?()
        default:
            guard let ordinal = Int(key), (1...9).contains(ordinal), onSelectMatch?(ordinal) == true else {
                return super.performKeyEquivalent(with: event)
            }
        }
        return true
    }

    override func keyDown(with event: NSEvent) {
        log.debug("overview: keyDown \(event.keyCode)")
        if let key = FilterKey(event: event), onKey?(key) == true { return }
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

    /// A fixed palette also needs the parts macOS draws itself — the backdrop blur, any
    /// system material — in its own appearance; otherwise Tokyo Night sits on a light blur
    /// while the system is in light mode.
    func applyAppearance(_ scheme: ColorScheme?) {
        appearance = scheme.map { NSAppearance(named: $0 == .dark ? .darkAqua : .aqua) } ?? nil
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

/// AppKit's half of `FilterKey`, which lives in `Common` and may not see an `NSEvent`.
/// A modified key is somebody else's (Cmd-Q, Cmd-W, Ctrl-arrows in AeroSpace); Shift is
/// not a modifier here, it is how capitals are typed.
private extension FilterKey {
    init?(event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control, .option]) else { return nil }
        switch event.keyCode {
        case 53: self = .escape
        case 51: self = .backspace
        case 36, 76: self = .enter
        default:
            guard let key = event.characters?.first.flatMap(FilterKey.typed) else { return nil }
            self = key
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
