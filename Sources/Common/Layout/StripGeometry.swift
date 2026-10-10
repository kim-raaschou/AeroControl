import CoreGraphics

public enum StripGeometry {
    public static let tallest: CGFloat = 0.85
    public static let tallestOfSeveral: CGFloat = 0.33
    public static let seen: CGFloat = 3.5

    public static func cardHeight(view: CGFloat, cards: Int, aspect: CGFloat, chrome: CGFloat, panelHeight: CGFloat) -> CGFloat {
        let each = view / min(CGFloat(max(1, cards)), seen) - chrome
        return min((panelHeight * (cards > 1 ? tallestOfSeveral : tallest)).rounded(), (each / max(0.01, aspect)).rounded(.down))
    }

    public struct Span: Equatable, Sendable {
        public let x: CGFloat
        public let width: CGFloat
    }
}
