import SwiftUI
import Common

struct AeroControlPanel: View {
    let state: OverviewStore
    @Environment(\.aeroLook) private var look
    @Namespace private var tiles

    init(state: OverviewStore) { self.state = state }

    var body: some View {
        let scene = state.scene
        return VStack(spacing: AeroControlLayout.pillGap) {
            switch scene.body {
            case .nothing: EmptyView()
            case .strip: AeroControlAppStrip(scene: scene, tiles: tiles)
            case .map: grid(scene)
            }
            AeroControlFilterPill(lane: scene.lane)
        }
        .fixedSize()
        .environment(state)
        .environment(\.aeroLook, AeroLook(palette: look.palette, motion: look.motion, surface: scene.body == .strip ? .strip : .map))
    }

    private func grid(_ scene: OverviewScene) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(scene.cards, id: \.workspace.name) { card in
                AeroControlWorkspaceCard(card: card, tiles: tiles)
                    .offset(x: card.frame.minX, y: card.frame.minY)
                    .transition(unsafe .opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .frame(width: scene.size.width, height: scene.size.height, alignment: .topLeading)
        .onAppear { state.notePointer(NSEvent.mouseLocation) }
        .animation(.easeInOut(duration: 0.15 * look.motion), value: scene.cards.map(\.workspace))
    }
}
