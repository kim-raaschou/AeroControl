import SwiftUI
import Common

struct AeroControlFilterPill: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    let lane: OverviewScene.Lane

    private static let mapKeys = "←→↑↓ move · ⏎ focus"

    var body: some View {
        Group {
            switch lane {
            case .notice(let name, let reason): appPill(name, icon: nil, summary: reason, keys: "esc  close")
            case .app(let name, let bundleId, let summary): appPill(name, icon: state.pictures.icon(for: bundleId), summary: summary, keys: Self.mapKeys)
            case .query(let query, let miss): pill(query, miss: miss)
            case .keys: keys(Self.mapKeys)
            }
        }
        .frame(height: AeroControlLayout.pillLane)
    }

    private func keys(_ text: String) -> some View {
        Text(text)
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(look.palette.badgeText.opacity(0.4))
    }

    private func appPill(_ name: String, icon: NSImage?, summary: String, keys hint: String) -> some View {
        HStack(spacing: 8) {
            if let icon {
                PixelImage(image: Image(nsImage: icon), size: CGSize(width: 20, height: 20))
            }
            Text(name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("· " + summary)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .opacity(0.75)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: Self.titleWidth, alignment: .leading)
                .fixedSize()
            keys(hint).padding(.leading, 12)
        }
        .capsule(look.palette)
    }

    private static let titleWidth: CGFloat = 560

    private func pill(_ query: String, miss: Bool) -> some View {
        HStack(spacing: 8) {
            Text(query)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if miss {
                Text("no match")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .opacity(0.75)
            }
        }
        .capsule(look.palette)
    }
}

private extension View {
    func capsule(_ palette: AeroControlPalette) -> some View {
        foregroundStyle(palette.badgeText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(palette.badgeFill, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }
}
