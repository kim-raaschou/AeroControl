import CoreGraphics

/// The layout axis of the free-floating overview widget. The overview is always a
/// single, content-sized widget on the focused display; orientation only decides how
/// its workspace cards are laid out. Derived from the widget's dock `DockEdge`, never
/// chosen on its own.
public enum Orientation: String, Equatable, Sendable {
    /// Workspace cards laid out left-to-right; each card is a horizontal row of app
    /// icons. The widget is wide and short.
    case horizontal
    /// Workspace cards stacked top-to-bottom; each card is a vertical column of app
    /// icons. The widget is tall and narrow.
    case vertical

    /// True for the vertical layout, which drives the axis used by the panel and the
    /// workspace cards.
    public var isVertical: Bool { self == .vertical }
}

/// Where the floating widget docks when placed from the **Position** menu. The single
/// control the user picks: it decides both where the widget sits *and* its layout axis —
/// top/bottom/center are horizontal (wide, short), left/right are vertical (tall,
/// narrow) — so orientation is derived, never chosen separately. `center` floats it in
/// the middle of the focused screen (a cmd-tab-style HUD).
public enum DockEdge: String, Equatable, Sendable, CaseIterable {
    case top, bottom, left, right, center

    /// The layout axis implied by this position: horizontal along the top/bottom and for
    /// the centered HUD, vertical down the left/right.
    public var orientation: Orientation {
        switch self {
        case .top, .bottom, .center: return .horizontal
        case .left, .right: return .vertical
        }
    }
}
