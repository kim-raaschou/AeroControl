import CoreGraphics

public enum Orientation: String, Equatable, Sendable {
    case horizontal
    case vertical

    public var isVertical: Bool { self == .vertical }
}

public enum DockEdge: String, Equatable, Sendable, CaseIterable, Codable {
    case menuBar, top, bottom, left, right, center

    public var orientation: Orientation {
        switch self {
        case .top, .bottom, .center, .menuBar: return .horizontal
        case .left, .right: return .vertical
        }
    }

    public var isMenuBar: Bool { self == .menuBar }
}
