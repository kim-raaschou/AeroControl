import AppKit
import AeroControlKit
import SwiftUI

// MARK: - Floating content-sized NSPanel

/// Hosting view that delivers the very first click straight to SwiftUI, even
/// though the overlay panel is a non-activating panel that is not the key
/// window. Without this, the first tap on a workspace/app (tap-to-focus) would be
/// swallowed just to (attempt to) focus the window, so click-to-focus would appear
/// dead.
final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    /// After layout, called with the content's natural fitting size, so the owning
    /// window can resize itself to hug the cards.
    var onContentResize: ((NSSize) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The widget is placed programmatically (follow-focus + the Position menu); no part
    /// of it drags the window, so a stray background click must never move it.
    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        if let onContentResize {
            onContentResize(fittingSize)
        }
    }
}

class OverviewWindow: NSPanel {
    private var targetScreen: NSScreen
    /// True for a vertical widget (left/right dock, cards stacked); false for a
    /// horizontal one (top/bottom/center, cards in a row). Only used to decide when a
    /// Position change flips the axis and the panel must be re-measured.
    private var isVertical: Bool
    /// True once the panel has faded in, so later programmatic reframes don't replay
    /// the show animation.
    private var hasFadedIn = false
    /// Where the widget docks on its screen (from the Position menu). Drives the
    /// placement in `clampedOrigin`.
    private var placementEdge: DockEdge

    init(targetScreen: NSScreen, edge: DockEdge = .top) {
        self.targetScreen = targetScreen
        self.placementEdge = edge
        self.isVertical = edge.orientation.isVertical
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        // A soft drop shadow lifts the floating widget clearly above the windows it
        // hovers over — it reads as a distinct panel, not part of the desktop.
        hasShadow = true
        titlebarAppearsTransparent = true
        // Deliver hover (mouse-moved) events so the cards' hover affordances —
        // notably the per-app close button — appear even though the panel never
        // becomes key.
        acceptsMouseMovedEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
    }

    override var canBecomeKey: Bool { false }

    // MARK: - Floating widget

    private weak var floatingHostingView: NSView?

    /// Installs the floating panel's content: the content-sized hosting view fills the
    /// window (which then tracks its fitting size).
    func installFloatingContent(hosting: NSView) {
        contentView = hosting
        floatingHostingView = hosting
    }

    /// Shows the content-sized floating panel at its docked placement. `contentSize` is
    /// the hosting view's size; the final frame is always clamped so the whole panel
    /// stays on-screen.
    func showFloating(contentSize: NSSize) {
        let origin = clampedOrigin(for: contentSize)
        setFrame(NSRect(origin: origin, size: contentSize), display: true)
        if hasFadedIn {
            // Only re-order a *visible* window front. A programmatic retarget (a focus
            // or monitor change routed through syncWindows) must not resurrect a widget
            // the user has hidden with the summon key — the show path orders it front
            // explicitly via revealFloating().
            if isVisible { orderFrontRegardless() }
        } else {
            // Fast fade-in on first show, so the widget appears to float in above the
            // desktop rather than snapping into place.
            hasFadedIn = true
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                animator().alphaValue = 1
            }
        }
    }

    /// Resizes the floating panel to newly-measured content, re-docking to its
    /// placement so a docked (or centered) widget stays put as it grows. No-op if the
    /// size hasn't meaningfully changed.
    func resizeFloating(toContent contentSize: NSSize) {
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        guard abs(contentSize.width - frame.width) > 0.5 || abs(contentSize.height - frame.height) > 0.5 else {
            return
        }
        let origin = clampedOrigin(for: contentSize)
        setFrame(NSRect(origin: origin, size: contentSize), display: true)
    }

    /// Retargets the floating panel to a different screen, re-placing it at its docked
    /// position at the current content size.
    func retargetFloating(to screen: NSScreen) {
        targetScreen = screen
        showFloating(contentSize: frame.size)
    }

    /// Fades the panel back in and orders it front — the show half of the summon-key
    /// show/hide toggle. The manager retargets to the focused screen first (which
    /// leaves the panel ordered-out at alpha 0), so this only animates the reveal.
    func revealFloating() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    /// Docks the widget at `edge` (Position menu): the edge sets both the layout axis
    /// and the on-screen anchor. Always re-measures the panel — the axis may flip
    /// (top↔left) *or* the effective icon size may change (menu-bar mode forces a native
    /// size), and a stale fitting size would snap the window to the wrong shape — then
    /// snaps to the new placement in one reframe.
    func applyEdge(_ edge: DockEdge) {
        placementEdge = edge
        isVertical = edge.orientation.isVertical
        floatingHostingView?.needsLayout = true
        floatingHostingView?.layoutSubtreeIfNeeded()
        let content = floatingHostingView?.fittingSize ?? frame.size
        showFloating(contentSize: content)
    }

    /// Converts the docked placement into a bottom-left origin, clamped so the whole
    /// panel stays within the screen frame (which includes the menu-bar band, so the
    /// panel may sit over the menu bar).
    private func clampedOrigin(for size: NSSize) -> CGPoint {
        let screenFrame = targetScreen.frame
        let visible = targetScreen.visibleFrame
        // Position-menu placement: the widget docks to `placementEdge`, centered along
        // that edge with a small inset; `center` floats it in the middle of the screen.
        let inset: CGFloat = 4
        let desiredTopLeft: CGPoint
        switch placementEdge {
        case .top:
            desiredTopLeft = CGPoint(x: visible.midX - size.width / 2, y: visible.maxY - inset)
        case .bottom:
            desiredTopLeft = CGPoint(x: visible.midX - size.width / 2, y: visible.minY + size.height + inset)
        case .left:
            desiredTopLeft = CGPoint(x: visible.minX + inset, y: visible.midY + size.height / 2)
        case .right:
            desiredTopLeft = CGPoint(x: visible.maxX - size.width - inset, y: visible.midY + size.height / 2)
        case .center:
            desiredTopLeft = CGPoint(x: visible.midX - size.width / 2, y: visible.midY + size.height / 2)
        case .menuBar:
            // Centered on the macOS menu-bar band: horizontally at the screen's midpoint
            // and vertically on the middle of the band (between the menu bar's bottom edge
            // `visible.maxY` and the screen's top `screenFrame.maxY`), so the strip sits
            // balanced on the menu-bar line rather than hanging below it.
            let bandMidY = (visible.maxY + screenFrame.maxY) / 2
            desiredTopLeft = CGPoint(x: visible.midX - size.width / 2, y: bandMidY + size.height / 2)
        }
        var originX = desiredTopLeft.x
        var originY = desiredTopLeft.y - size.height
        let minX = screenFrame.minX
        let maxX = screenFrame.maxX - size.width
        let minY = screenFrame.minY
        let maxY = screenFrame.maxY - size.height
        // When the widget fits, clamp normally. When it's larger than the screen in a
        // dimension it cannot fully fit, align to the top-left so the start of the
        // content stays reachable.
        originX = minX <= maxX ? min(max(originX, minX), maxX) : minX
        originY = minY <= maxY ? min(max(originY, minY), maxY) : maxY
        return CGPoint(x: originX, y: originY)
    }
}
