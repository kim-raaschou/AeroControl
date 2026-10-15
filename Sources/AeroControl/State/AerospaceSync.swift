import Common
import Foundation

@MainActor
final class AerospaceSync {
    private let runner: AerospaceProcessRunner
    private var refreshing: Task<Void, Never>?
    static let readAfter: Duration = .milliseconds(20)
    static let readAgainAfter: Duration = .milliseconds(150)
    static let focusAgainAfter: Duration = .milliseconds(300)

    init(runner: AerospaceProcessRunner) { self.runner = runner }

    func read() async -> Result<OverviewModel, Error> {
        do { return .success(try await loadOverview(using: runner)) } catch { return .failure(error) }
    }

    func listen(_ received: @escaping @MainActor (AerospaceEvent) -> Void, resumed: @escaping @MainActor () async -> Void) {
        Task.detached(priority: .utility) { [runner] in
            var reconnecting = false
            while true {
                let events = runner.subscribe(AerospaceCommand.subscribe).compactMap(AerospaceEvent.parse)
                if let mode = try? await runner.run(AerospaceCommand.currentMode) { await received(.mode(mode)) }
                if reconnecting { await resumed() }
                do { for try await event in events { await received(event) } } catch {}
                reconnecting = true
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var commanded = 0
    private var queue: Task<Void, Never>?

    func run(_ actions: [AeroControlAction]) async {
        commanded &+= 1
        let mine = commanded, before = queue
        let turn = Task { [runner] in
            await before?.value
            for action in actions { _ = try? await runner.run(AerospaceCommand.argv(for: action)) }
        }
        queue = turn
        await turn.value
        if case .focusWindow(let id) = actions.last { await focusAgainIfMissed(id, unlessAfter: mine) }
    }

    func refresh(_ land: @escaping @MainActor (Result<OverviewModel, Error>, _ again: Bool) async -> Void) {
        refreshing?.cancel()
        refreshing = Task {
            for (wait, again) in [(Self.readAfter, false), (Self.readAgainAfter, true)] {
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
                let read = await read()
                guard !Task.isCancelled else { return }
                await land(read, again)
            }
        }
    }

    func stop() { refreshing?.cancel() }

    /// WORKAROUND for AeroSpace issue 101, https://github.com/nikitabobko/AeroSpace/issues/101 —
    /// remove once AeroSpace fixes it. Asked to focus a window of an app that has windows on more
    /// than one monitor, AeroSpace activates the app, and macOS, as the activation completes, gives
    /// the keyboard back to the app's last key window, often on the other monitor; AeroSpace
    /// follows. Asked again once the app is active, the focus holds. So a moment after a focus,
    /// if AeroSpace's focus is elsewhere and nothing else was commanded since, it is asked for once more.
    private func focusAgainIfMissed(_ windowId: Int, unlessAfter mine: Int) async {
        try? await Task.sleep(for: Self.focusAgainAfter)
        guard mine == commanded else { return }
        if await loadFocusedWindow(using: runner)?.windowId != windowId { _ = try? await runner.run(AerospaceCommand.argv(for: .focusWindow(windowId))) }
    }
}
