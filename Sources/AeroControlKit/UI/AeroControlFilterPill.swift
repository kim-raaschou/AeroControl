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
    let matchCount: Int

    private var query: String { state.filter }

    private var app: StripApp? {
        if let missing = state.missingApp?.notFound { return StripApp(name: missing.name, icon: nil, summary: missing.reason, keys: "esc  close") }
        if let strip = state.strip, let first = state.stripWindows.first?.window {
            return StripApp(name: first.appName, icon: state.pictures.icon(for: strip.app ?? ""),
                            summary: AppStripModel.summary(state.stripWindows, marked: strip.marked), keys: "← → ↑ ↓ move  ·  ⌘← ⌘→ workspace  ·  ⇧⌘x move to x  ·  ⏎ focus")
        }
        guard let marked = state.marking?.marked, let ringed = state.model.windowsInGridOrder.first(where: { $0.window.windowId == marked }) else { return nil }
        return StripApp(name: ringed.window.appName, icon: state.pictures.icon(for: ringed.window.bundleId), summary: ringed.window.caption + " · ws " + ringed.workspace, keys: Self.mapKeys)
    }
    private static let mapKeys = "type to filter  ·  ← → ↑ ↓ move  ·  ⌘← ⌘→ ⌘↑ ⌘↓ workspace  ·  ⇧⌘x move to x  ·  ⏎ focus"

    var body: some View {
        Group {
            if let app { appPill(app) } else if query.isEmpty { hint } else { pill }
        }
        .frame(height: AeroControlLayout.pillLane)
    }

    private var hint: some View { keys(Self.mapKeys) }

    private func keys(_ text: String) -> some View {
        Text(text)
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

    private var pill: some View {
        HStack(spacing: 8) {
            Text(query)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            if matchCount == 0, query.trimmingCharacters(in: .whitespaces).count >= OverviewModel.minQueryLength {
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
