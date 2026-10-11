import SwiftUI
import Common

struct AeroControlAppStrip: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    let scene: OverviewScene
    let tiles: Namespace.ID

    private static let turn: Double = 0.4
    private static let cutCard: Double = 0.5

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(scene.cards, id: \.workspace.name) { card in
                AeroControlCardFace(card: card, tiles: tiles)
                    .opacity(card.cut ? Self.cutCard : 1)
                    .offset(x: card.frame.minX)
            }
        }
        .frame(width: scene.size.width, height: scene.cards.first?.frame.height ?? 0, alignment: .topLeading)
        .clipped()
        .animation(.smooth(duration: Self.turn * look.motion), value: scene.held ?? -1)
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
    }
}
