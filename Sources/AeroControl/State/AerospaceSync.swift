import Common
import Foundation

@MainActor
final class AerospaceSync {
    private let runner: AerospaceProcessRunner
    private var refreshing: Task<Void, Never>?
    static let readAfter: Duration = .milliseconds(20)
    static let readAgainAfter: Duration = .milliseconds(150)

    init(runner: AerospaceProcessRunner) { self.runner = runner }

    func read() async -> Result<OverviewModel, Error> {
        do { return .success(try await loadOverview(using: runner)) } catch { return .failure(error) }
    }

    func listen(_ received: @escaping @MainActor (AerospaceEvent) -> Void) {
        Task.detached(priority: .utility) { [runner] in
            while true {
                let events = runner.subscribe(AerospaceCommand.subscribe).compactMap(AerospaceEvent.parse)
                await received(.changed)
                for await event in events { await received(event) }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var queue: Task<Void, Never>?

    func run(_ actions: [AeroControlAction]) async {
        let before = queue
        let turn = Task { [runner] in
            await before?.value
            for action in actions { _ = try? await runner.run(AerospaceCommand.argv(for: action)) }
        }
        queue = turn
        await turn.value
    }

    func refresh(_ land: @escaping @MainActor (Result<OverviewModel, Error>, _ again: Bool) async -> Void) {
        refreshing?.cancel()
        refreshing = Task {
            for (wait, again) in [(Self.readAfter, false), (Self.readAgainAfter, true)] {
                try? await Task.sleep(for: wait)
                guard !Task.isCancelled else { return }
                let read = await read()
                guard !Task.isCancelled else { return }
                if case .failure = read, !again { continue }
                await land(read, again)
            }
        }
    }

    func stop() { refreshing?.cancel() }
}
