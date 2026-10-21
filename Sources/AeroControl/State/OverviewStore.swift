import AppKit
import Common
import Observation

@MainActor @Observable
class OverviewStore {
    private(set) var visit = Visit()
    static let repaintedAfter: Duration = .milliseconds(1500)

    private let sync: AerospaceSync
    let pictures: PictureStore
    private(set) var error: String?
    var screen: (available: CGSize, frames: [Int: CGRect], scale: CGFloat) = (.zero, [:], 1)
    private var following: Bool { visit.visible && !visit.loading }
    var onEffect: ((Visit.Host) -> Void)?

    var scene: OverviewScene { OverviewScene(visit, error: error, available: screen.available, screens: screen.frames, frames: pictures.frames) }

    init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.sync = AerospaceSync(runner: runner)
        self.pictures = PictureStore(bridge: nativeSystem)
    }

    func update(_ body: (inout Visit) -> [Visit.Effect]) {
        var next = visit
        let effects = body(&next)
        if next != visit { visit = next }
        for effect in effects {
            switch effect {
            case .refresh: requestRefresh()
            case .run(let actions, let thenRead): Task { await sync.run(actions); if thenRead, following { requestRefresh() } }
            case .host(let effect): onEffect?(effect)
            }
        }
    }

    func send(_ input: Visit.Input) { update { $0.apply(input) } }

    func handle(_ key: FilterKey) {
        let drawn = scene.grid
        update { $0.key(key, drawn: drawn) }
        Task { _ = await retakePictures() }
    }

    private func retakePictures() async -> [Int: CGSize] { await pictures.retake(scene.pictureSizes(scale: screen.scale)) }

    func summon(_ summon: Summon) { let drawn = scene.grid; update { $0.summon(summon, drawn: drawn) } }
    @ObservationIgnored private var pointer: CGPoint?
    func notePointer(_ location: CGPoint) { pointer = location }
    func point(_ windowId: Int, at location: CGPoint) {
        guard location != pointer else { return }
        pointer = location
        update { $0.point(windowId); return [] }
    }

    private var repaint: Task<Void, Never>?

    func endVisit() {
        sync.stop()
        repaint?.cancel()
        update { $0.end(); return [] }
        pictures.clear()
    }

    private func reload() async { if let result = landed(await sync.read()) { send(.loaded(result)) } }

    private func landed(_ read: Result<OverviewModel, Error>) -> OverviewModel? {
        switch read {
        case .success(let result): error = nil; return result
        case .failure(let failure): error = failure.localizedDescription; return nil
        }
    }

    func open(_ summon: Summon, reveal: () -> Void) async {
        endVisit()
        pictures.prepare()
        await reload()
        update { $0.summoned(summon) }
        guard visit.visible else { return }
        pictures.measure(visit.model.workspaces.flatMap(\.windows).map(\.windowId))
        reveal()
        let scene = scene
        await pictures.take(scene.cards.map { $0.tiles.map(\.window.windowId) }, sizes: scene.pictureSizes(scale: screen.scale))
    }

    func startListening() {
        sync.listen({ event in
            if self.following { self.send(.event(event)) }
            if case .focusChanged(let id?, _) = event { self.update { $0.noteFocus(id); return [] } }
        }, resumed: { if self.following { await self.reload() } })
    }

    private func requestRefresh() {
        sync.refresh { read, again in
            if case .failure = read, !again { return }
            guard self.following, let result = self.landed(read) else { return }
            self.send(.loaded(result))
            guard self.following else { return }
            self.pictures.settle(result.workspaces.flatMap(\.windows).map(\.windowId))
            guard again else { return }
            let taken = await self.retakePictures()
            guard !taken.isEmpty else { return }
            self.repaint = Task {
                try? await Task.sleep(for: Self.repaintedAfter)
                guard !Task.isCancelled, self.following else { return }
                await self.pictures.shoot(self.scene.pictureSizes(scale: self.screen.scale).filter { taken[$0.key] != nil })
            }
        }
    }
}
