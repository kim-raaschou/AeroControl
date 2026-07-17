import AppKit
import AeroControlKit
import SwiftUI

final class InteractiveHostingView<Content: View>: NSHostingView<Content> {
    var onContentResize: ((NSSize) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func layout() {
        super.layout()
        if let onContentResize {
            onContentResize(fittingSize)
        }
    }
}

class OverviewWindow: NSPanel {
    private let targetScreen: NSScreen
    private var hasFadedIn = false
    private var placementEdge: DockEdge

    init(targetScreen: NSScreen, edge: DockEdge = .top) {
        self.targetScreen = targetScreen
        self.placementEdge = edge
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titlebarAppearsTransparent = true
        acceptsMouseMovedEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
        ]
    }

    override var canBecomeKey: Bool { false }

    private weak var floatingHostingView: NSView?

    func installFloatingContent(hosting: NSView) {
        contentView = hosting
        floatingHostingView = hosting
    }

    func showFloating(contentSize: NSSize) {
        let origin = clampedOrigin(for: contentSize)
        setFrame(NSRect(origin: origin, size: contentSize), display: true)
        if hasFadedIn {
            if isVisible { orderFrontRegardless() }
        } else {
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

    func resizeFloating(toContent contentSize: NSSize) {
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        guard abs(contentSize.width - frame.width) > 0.5 || abs(contentSize.height - frame.height) > 0.5 else {
            return
        }
        let origin = clampedOrigin(for: contentSize)
        setFrame(NSRect(origin: origin, size: contentSize), display: true)
    }

    func revealFloating() {
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func applyEdge(_ edge: DockEdge) {
        placementEdge = edge
        floatingHostingView?.needsLayout = true
        floatingHostingView?.layoutSubtreeIfNeeded()
        let content = floatingHostingView?.fittingSize ?? frame.size
        showFloating(contentSize: content)
    }

    private func clampedOrigin(for size: NSSize) -> CGPoint {
        let screenFrame = targetScreen.frame
        let visible = targetScreen.visibleFrame
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
            let bandMidY = (visible.maxY + screenFrame.maxY) / 2
            desiredTopLeft = CGPoint(x: visible.midX - size.width / 2, y: bandMidY + size.height / 2)
        }
        var originX = desiredTopLeft.x
        var originY = desiredTopLeft.y - size.height
        let minX = screenFrame.minX
        let maxX = screenFrame.maxX - size.width
        let minY = screenFrame.minY
        let maxY = screenFrame.maxY - size.height
        originX = minX <= maxX ? min(max(originX, minX), maxX) : minX
        originY = minY <= maxY ? min(max(originY, minY), maxY) : maxY
        return CGPoint(x: originX, y: originY)
    }
}
