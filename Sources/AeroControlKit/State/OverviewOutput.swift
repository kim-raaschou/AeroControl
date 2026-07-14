import Common

/// The `OverviewStore`'s typed output channel — the counterpart to its action/event
/// inputs. The host (AppDelegate) consumes a single `AsyncStream<OverviewOutput>` and
/// reacts to each case, instead of wiring up several ad-hoc closures.
public enum OverviewOutput: Equatable, Sendable {
    /// The initial load finished (successfully or not); the host reveals the overlay
    /// and shows an error fallback if `error` is set.
    case loaded
    /// The set of monitors hosting workspaces changed; the host re-syncs windows.
    case monitorsChanged
    /// A workspace gained focus. Currently no host-side reaction (the floating widget
    /// never disturbs window positions); retained as a meaningful store event.
    case workspaceFocused(WorkspaceInfo)
    /// The reconciled, rendered model changed (a window opened/closed/moved, or focus
    /// shifted) without the monitor set changing. The manually-hosted `NSHostingView`
    /// does not auto-observe `@Observable` model changes, so the host rebuilds the
    /// panel's root view to reflect the new state.
    case contentChanged
}
