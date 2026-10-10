import Common
import SwiftUI

struct AeroControlKeyHelp: View {
    @Environment(OverviewStore.self) private var state
    @Environment(\.aeroLook) private var look

    var body: some View {
        let rows = state.strip != nil ? KeyHelp.strip : KeyHelp.map
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
            ForEach(rows, id: \.keys) { row in
                GridRow {
                    Text(row.keys).font(.system(size: 13, weight: .semibold, design: .rounded)).gridColumnAlignment(.trailing)
                    Text(row.does).font(.system(size: 13))
                }
            }
        }
        .padding(22)
        .foregroundStyle(look.palette.badgeText)
        .background(look.palette.cardFill ?? Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AeroControlLayout.cardRadius, style: .continuous).strokeBorder(look.palette.cardBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
        .onTapGesture { state.showingHelp = false }
    }
}
