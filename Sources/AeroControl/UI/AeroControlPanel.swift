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
            case .nothing: if case .notice(let name, let reason) = scene.lane { notice(name, reason) }
            case .strip: AeroControlAppStrip(scene: scene, tiles: tiles)
            case .map: grid(scene)
            }
            AeroControlFilterPill(lane: scene.lane)
        }
        .fixedSize()
        .environment(state)
        .environment(\.aeroLook, AeroLook(palette: look.palette, motion: look.motion, surface: scene.body == .strip ? .strip : .map))
    }

    private func notice(_ name: String, _ reason: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 30)).foregroundStyle(.orange)
            Text(name).font(.system(size: 22, weight: .bold, design: .rounded))
            Text(reason).font(.system(size: 15, weight: .medium, design: .rounded)).opacity(0.8)
        }
        .foregroundStyle(look.palette.badgeText)
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous).strokeBorder(look.palette.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
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
