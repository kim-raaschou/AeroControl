import Foundation

public enum AppSummon: Equatable, Sendable {
    case launch(AppRef)
    case focus(windowId: Int)
    case pick(Strip)

    public static func decide(app ref: AppRef, model: OverviewModel, recent: [Int]) -> AppSummon {
        let windows = model.windowsInGridOrder.map(\.window).filter(ref.matches)
        let focusedAt = windows.firstIndex { $0.windowId == model.focusedWindowId }
        if windows.count == 1 { return .focus(windowId: windows[0].windowId) }
        guard windows.count > 1 else { return .launch(ref) }
        if windows.count == 2, let focusedAt { return .focus(windowId: windows[1 - focusedAt].windowId) }
        return .pick(.opened(windows[0].bundleId, origin: focusedAt.map { _ in model.focusedWindowId }, ids: windows.map(\.windowId), recent: recent))
    }
}
