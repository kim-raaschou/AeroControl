import Foundation

/// The app strip — the picker for "which of this app's windows": one row of groups, one
/// per workspace holding the app, every tile at its own shape and all at one picture
/// height. The height is as large as the view allows, between a fifth and a half of the
/// screen, so two windows are two big pictures and nine are still a row. Ported from
/// krn.overview's AppStrip.
public enum AppStripLayout {
    public struct Group: Equatable, Sendable {
        /// The plate's left edge and width, padding included.
        public let x: CGFloat
        public let width: CGFloat
        /// The group's tiles, `x` measured from the strip's left edge.
        public let tiles: [TilePacker.Tile]
    }

    public struct Layout: Equatable, Sendable {
        /// Picture height; a tile is this plus the caption.
        public let height: CGFloat
        public let width: CGFloat
        public let groups: [Group]
    }

    /// `groups` are each workspace's windows as width / height ratios, in grid order.
    public static func layout(groups: [[CGFloat]], viewWidth: CGFloat, panelHeight: CGFloat,
                              tileGap: CGFloat, groupGap: CGFloat, caption: CGFloat,
                              groupPadding: CGFloat = 0) -> Layout {
        let ratios = groups.flatMap { $0 }
        guard !ratios.isEmpty else { return Layout(height: 0, width: 0, groups: []) }
        let gaps = tileGap * CGFloat(groups.reduce(0) { $0 + max(0, $1.count - 1) }) + groupGap * CGFloat(groups.count - 1)
            + 2 * groupPadding * CGFloat(groups.count)
        let fitting = ((viewWidth - gaps) / ratios.reduce(0, +)).rounded(.down)
        let height = min((panelHeight * 0.5).rounded(), max((panelHeight * 0.2).rounded(), fitting))
        var x: CGFloat = 0
        var laid: [Group] = []
        for (g, group) in groups.enumerated() {
            if g > 0 { x += groupGap }
            let start = x
            x += groupPadding
            var tiles: [TilePacker.Tile] = []
            for (t, ratio) in group.enumerated() {
                if t > 0 { x += tileGap }
                let width = (ratio * height).rounded(.down)
                tiles.append(TilePacker.Tile(x: x, y: 0, width: width, height: height + caption))
                x += width
            }
            x += groupPadding
            laid.append(Group(x: start, width: x - start, tiles: tiles))
        }
        return Layout(height: height, width: x, groups: laid)
    }
}
