# Kit · UI

SwiftUI views that draw what the stores hold and send what the user does. They read `OverviewStore` from the environment and `AeroLook` — the palette, the motion scale and the surface, map or strip — and they compute nothing the store could: the layout comes from `OverviewStore.cards` and `OverviewStore.stripLayout`.

**`AeroControlPanel`** is the whole overview: the map of workspace cards, or the strip, with the pill underneath. **`AeroControlWorkspaceCard`** is one workspace on the map, a drop target for tiles and other cards; **`AeroControlCardFace`** is the card's chrome, shared with the strip; **`AeroControlAppStrip`** is one app's workspaces in a sliding row. **`AeroControlAppTile`** is one window: its picture covering its slot and cut at the edges, the ring, the close button, the key in the strip, the live picture when it wears the ring. **`AeroControlFilterPill`** is the lane under the cards: the query, the strip's line, or the keys that work. **`AeroControlTheme`** is the palettes.

**Rules.** A tile is the same view wherever it is drawn (`matchedGeometryEffect`), so a window that moves glides. Pictures are drawn at exact pixels (`PixelImage`). The leaves draw by `AeroLook.surface`, not by asking the store what is up. The lane is reserved, not added, so typing never moves a card.
