import SwiftUI
import Common

struct AeroControlWorkspaceCard: View {
    let workspace: WorkspaceInfo
    let isFocused: Bool
    let focusedWindowId: Int
    let icons: [Int: NSImage]
    let iconSize: CGFloat
    let onFocusWorkspace: () -> Void
    let onFocusWindow: (Int) -> Void
    let onMoveWindow: (Int, String) -> Void
    let onCloseWindow: (Int) -> Void
    var isVertical: Bool = false

    @State private var isDropTarget = false
    @Environment(\.colorScheme) private var colorScheme

    @ScaledMetric(relativeTo: .caption) private var typeScale: CGFloat = 1
    private var clampedTypeScale: CGFloat { min(max(typeScale, 1), 1.5) }

    private var metrics: AeroControlMetrics { AeroControlMetrics(iconSize: iconSize) }
    private var cornerRadius: CGFloat { metrics.cornerRadius }

    var body: some View {
        content
            .dropDestination(for: WindowDragData.self) { items, _ in
                guard let item = items.first else { return false }
                isDropTarget = false
                onMoveWindow(item.windowId, workspace.name)
                return true
            } isTargeted: { isDropTarget = $0 }
    }

    @ViewBuilder private var content: some View {
        if workspace.windows.isEmpty {
            emptyPill
        } else {
            cardContent
        }
    }

    private var emptyPill: some View {
        withFocusPlate {
            if isVertical {
                Color.clear
                    .frame(height: metrics.emptyCardWidth)
                    .frame(maxWidth: .infinity)
            } else {
                Color.clear
                    .frame(width: metrics.emptyCardWidth)
                    .frame(maxHeight: .infinity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onFocusWorkspace)
    }

    @ViewBuilder private func withFocusPlate(@ViewBuilder _ content: () -> some View) -> some View {
        content()
            .overlay(alignment: .topLeading) { badge.allowsHitTesting(false) }
            .modifier(FocusPlate(isFocused: isFocused, cornerRadius: cornerRadius))
            .overlay(dropTargetHint.allowsHitTesting(false))
    }

    private var cardContent: some View {
        withFocusPlate {
            appRow
                .padding(.top, metrics.cardTopPadding)
                .padding(.bottom, metrics.cardBottomPadding)
                .padding(.horizontal, metrics.cardHorizontalPadding)
                .frame(
                    maxWidth: isVertical ? .infinity : nil,
                    maxHeight: isVertical ? nil : .infinity,
                    alignment: isVertical ? .leading : .top
                )
                .background {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onFocusWorkspace)
                }
        }
    }

    private var badge: some View {
        Text(workspace.name)
            .font(.system(size: metrics.badgeFontSize * clampedTypeScale, weight: .bold, design: .rounded))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.primary)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.55 : 0.18), radius: 1.5, x: 0, y: 0.5)
            .padding(.horizontal, metrics.badgePaddingH)
            .padding(.vertical, metrics.badgePaddingV)
            .background(badgeFill, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    .white.opacity(colorScheme == .dark ? 0.25 : 0.4),
                    lineWidth: 1
                )
            )
            .padding(.leading, metrics.badgeInset)
            .padding(.top, metrics.badgeInset)
            .padding(.trailing, metrics.badgeInset)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var badgeFill: Color {
        colorScheme == .dark ? .black.opacity(0.45) : .white.opacity(0.72)
    }

    private var appRow: some View {
        let layout = isVertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: metrics.appRowSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: metrics.appRowSpacing))
        return layout {
            ForEach(workspace.windows, id: \.windowId) { window in
                AeroControlAppTile(
                    window: window,
                    image: icons[window.windowId],
                    isFocused: window.windowId == focusedWindowId,
                    onFocusWindow: { onFocusWindow(window.windowId) },
                    onCloseWindow: { onCloseWindow(window.windowId) },
                    iconSize: iconSize
                )
            }
        }
        .animation(.easeInOut(duration: 0.15), value: workspace.windows)
    }

    @ViewBuilder private var dropTargetHint: some View {
        if isDropTarget {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 2)
        }
    }
}

private struct FocusPlate: ViewModifier {
    let isFocused: Bool
    let cornerRadius: CGFloat
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if reduceTransparency {
            content
                .background {
                    shape
                        .fill(opaqueBase)
                        .overlay { if isFocused { shape.fill(Color.accentColor.opacity(0.5)) } }
                }
        } else {
            content
                .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
                .overlay {
                    shape.fill(frostBody).allowsHitTesting(false)
                }
                .overlay {
                    shape.strokeBorder(
                        isFocused ? Color.accentColor.opacity(0.95) : crispEdge,
                        lineWidth: isFocused ? 1.75 : 1.25
                    )
                    .allowsHitTesting(false)
                }
        }
    }

    private var frostBody: Color {
        colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.12)
    }

    private var crispEdge: Color {
        colorScheme == .dark ? .white.opacity(0.45) : .white.opacity(0.65)
    }

    private var opaqueBase: Color {
        colorScheme == .dark ? Color(white: 0.22) : Color(white: 0.90)
    }
}
