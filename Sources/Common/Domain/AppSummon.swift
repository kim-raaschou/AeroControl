import Foundation

/// What one key on an app does, decided from AeroSpace's state alone. Three of the four
/// cases are settled at once and without a word; the fourth, windows to choose between, is
/// the strip, and the strip to open comes with it.
public enum AppSummon: Equatable, Sendable {
    /// Start the app, or bring it forward if it runs; its windows are macOS's to order.
    case launch(bundleId: String)
    /// One window is the answer: focus it, and show nothing.
    case focus(windowId: Int)
    /// Windows to choose between: show the strip, opened like this.
    case pick(Strip)

    /// The rule: none, start; one, focus it; two and you are in one, the other; otherwise the
    /// strip, when the picker is on, or the app brought forward when it is off.
    public static func decide(app bundleId: String, model: OverviewModel, recent: [Int], picker: Bool) -> AppSummon {
        let windows = model.windowsInGridOrder.map(\.window).filter { $0.bundleId == bundleId }
        let focusedAt = windows.firstIndex { $0.windowId == model.focusedWindowId }
        switch windows.count {
        case 0: return .launch(bundleId: bundleId)
        case 1: return .focus(windowId: windows[0].windowId)
        default: break
        }
        guard picker else { return .launch(bundleId: bundleId) }
        if windows.count == 2, let focusedAt { return .focus(windowId: windows[1 - focusedAt].windowId) }
        return .pick(.opened(bundleId, origin: focusedAt.map { _ in model.focusedWindowId }, ids: windows.map(\.windowId), recent: recent))
    }
}
