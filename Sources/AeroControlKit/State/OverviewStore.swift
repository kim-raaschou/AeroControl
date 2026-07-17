import AppKit
import SwiftUI
import Common

@MainActor @Observable
public class OverviewStore {
    public private(set) var model = OverviewModel()

    let runner: AerospaceProcessRunner
    let nativeSystem: NativeApiBridge
    private(set) var icons: [Int: NSImage] = [:]
    public private(set) var error: String?

    public var onLoaded: (@MainActor () -> Void)?
    public var onMonitorsChanged: (@MainActor () -> Void)?

    private let inbox: AsyncStream<OverviewInput>
    private let inboxContinuation: AsyncStream<OverviewInput>.Continuation

    private var inboxTask: Task<Void, Never>?
    private var subscribeTask: Task<Void, Never>?
    private var terminationTask: Task<Void, Never>?
    private var windowCloseTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.runner = runner
        self.nativeSystem = nativeSystem
        (inbox, inboxContinuation) = AsyncStream.makeStream()
    }

    public func send(_ input: OverviewInput) {
        inboxContinuation.yield(input)
    }

    public func start() async {
        await initialLoad()
        startInbox()
        startSubscribeListener()
        startTerminationListener()
        startWindowCloseListener()
        fireLoadedAfterEffects()
    }

    private func fireLoadedAfterEffects() {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.onLoaded?()
            }
        }
    }

    private func initialLoad() async {
        let maxAttempts = 5
        var lastError: Error?
        for attempt in 1...maxAttempts {
            do {
                let result = try await loadOverview(using: runner)
                apply(.loaded(result), animated: false)
                self.error = nil
                return
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    try? await Task.sleep(for: .milliseconds(200 * attempt))
                }
            }
        }
        if let lastError {
            self.error = "Load error: \(lastError.localizedDescription)"
        }
    }

    public func stop() {
        inboxContinuation.finish()
        inboxTask?.cancel()
        inboxTask = nil
        subscribeTask?.cancel()
        subscribeTask = nil
        terminationTask?.cancel()
        terminationTask = nil
        windowCloseTask?.cancel()
        windowCloseTask = nil
        refreshTask?.cancel()
        refreshTask = nil
    }

    public func dispatch(_ action: AeroControlAction) async {
        send(.action(action))
    }

    private func startInbox() {
        guard inboxTask == nil else { return }
        inboxTask = Task { [weak self] in
            guard let self else { return }
            for await input in self.inbox {
                if Task.isCancelled { return }
                self.apply(input)
            }
        }
    }

    private func startSubscribeListener() {
        guard subscribeTask == nil else { return }
        subscribeTask = Task.detached(priority: .utility) { [weak self] in
            while let self, !Task.isCancelled {
                do {
                    let stream = self.runner.subscribe(AerospaceCommand.subscribe())
                    for try await line in stream {
                        if let event = AerospaceEvent.parse(line) {
                            await self.send(.event(event))
                        }
                    }
                } catch {}
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func startTerminationListener() {
        guard terminationTask == nil else { return }
        terminationTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.nativeSystem.appTerminations() {
                guard !Task.isCancelled else { return }
                self.send(.event(.localWindowClosed))
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(150))
                    self?.send(.event(.localWindowClosed))
                }
            }
        }
    }

    private func startWindowCloseListener() {
        guard windowCloseTask == nil else { return }
        windowCloseTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.nativeSystem.windowCloseSignals() {
                guard !Task.isCancelled else { return }
                self.send(.event(.localWindowClosed))
            }
        }
    }

    private func apply(_ input: OverviewInput, animated: Bool = true) {
        let (newState, effects) = Common.updateOverview(model, input)
        let focusChanged = newState.focusedWorkspace != model.focusedWorkspace
        if newState != model {
            if animated && !focusChanged {
                withAnimation(.easeInOut(duration: 0.1)) {
                    model = newState
                }
            } else {
                model = newState
            }
        }
        DispatchQueue.main.async { [self] in
            self.executeEffects(effects)
        }
    }

    private func executeEffects(_ effects: [OverviewEffect]) {
        for effect in effects {
            switch effect {
            case .windowRemoved(let id):
                icons.removeValue(forKey: id)
            case .loadIcons(let windows):
                var added: [Int: NSImage] = [:]
                for window in windows where icons[window.windowId] == nil {
                    added[window.windowId] = nativeSystem.appIcon(bundleId: window.bundleId)
                }
                if !added.isEmpty {
                    icons.merge(added) { _, new in new }
                }
            case .refresh:
                requestRefresh()
            case .monitorsChanged:
                onMonitorsChanged?()
            case .runAction(let action):
                runAction(action)
            }
        }
    }

    private func runAction(_ action: AeroControlAction) {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await self.runner.run(AerospaceCommand.argv(for: action))
            switch action {
            case .moveWindow, .closeWindow:
                self.requestRefresh()
            default:
                break
            }
        }
    }

    private var refreshGeneration = 0

    private func requestRefresh() {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            guard let result = try? await loadOverview(using: self.runner) else { return }
            guard generation == self.refreshGeneration else { return }
            self.error = nil
            self.send(.loaded(result))
        }
    }
}
