import CoreGraphics

/// The strip's geometry: how tall its cards are, how many the view holds, and a card's place on the row.
public enum StripGeometry {
    /// The most of the panel's height a strip card takes: one card, an app all on one workspace,
    /// all but fills it.
    public static let tallest: CGFloat = 0.85
    /// The most when the app is on more than one workspace: the strip is a view over several.
    public static let tallestOfSeveral: CGFloat = 0.33
    /// How many cards the view holds when the app is on more than one workspace, if the ceiling
    /// allows: three whole in the middle and, with more, a dimmed quarter of the next at each edge,
    /// so the row shows that it goes on.
    public static let seen: CGFloat = 3.5

    /// How tall the strip's cards are: one card fills the view's width, more each take a `seen`th
    /// of it, every card in its screen's shape (`aspect`) inside its `chrome`; never more than
    /// `tallest` of the panel, or `tallestOfSeveral` for several.
    public static func cardHeight(view: CGFloat, cards: Int, aspect: CGFloat, chrome: CGFloat, panelHeight: CGFloat) -> CGFloat {
        let each = view / min(CGFloat(max(1, cards)), seen) - chrome
        return min((panelHeight * (cards > 1 ? tallestOfSeveral : tallest)).rounded(), (each / max(0.01, aspect)).rounded(.down))
    }

    /// A card's place on the unrolled row.
    public struct Span: Equatable, Sendable {
        public let x: CGFloat
        public let width: CGFloat
    }
}
