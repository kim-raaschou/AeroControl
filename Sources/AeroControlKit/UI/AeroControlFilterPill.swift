import SwiftUI
import Common

struct AeroControlFilterPill: View {
    private struct StripApp {
        let name: String
        let icon: NSImage?
        let summary: String
        let keys: String
    }

    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look
    let lane: OverviewScene.Lane

    private var app: StripApp? {
        switch lane {
        case .notice(let name, let reason): StripApp(name: name, icon: nil, summary: reason, keys: "esc  close")
        case .app(let name, let bundleId, let summary): StripApp(name: name, icon: state.pictures.icon(for: bundleId), summary: summary, keys: Self.mapKeys)
        case .keys, .query: nil
        }
    }
    private static let mapKeys = "←→↑↓ move · ⏎ focus"

    var body: some View {
        Group {
            if let app { appPill(app) } else if case .query(let query, let miss) = lane { pill(query, miss: miss) } else { hint }
        }
        .frame(height: AeroControlLayout.pillLane)
    }

    private var hint: some View { keys(Self.mapKeys) }

    private func keys(_ text: String) -> some View {
        HStack(spacing: 10) {
            Text(text)
            Text("?")
                .padding(.horizontal, 6)
                .overlay(Capsule().strokeBorder(look.palette.badgeText.opacity(0.4), lineWidth: 1))
                .contentShape(Capsule())
                .onTapGesture { state.showingHelp.toggle() }
                .help("⌘/ — the keys")
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(look.palette.badgeText.opacity(0.4))
    }

    private func appPill(_ app: StripApp) -> some View {
        HStack(spacing: 8) {
            if let icon = app.icon {
                PixelImage(image: icon, size: CGSize(width: 20, height: 20))
            }
            Text(app.name)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            Text("· " + app.summary)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .opacity(0.75)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: Self.titleWidth, alignment: .leading)
                .fixedSize()
            keys(app.keys).padding(.leading, 12)
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
