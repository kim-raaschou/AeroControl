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
    private var following = false
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
            case .run(let actions, let thenRead): Task { await sync.run(actions); if thenRead { requestRefresh() } }
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

    func endVisit() {
        following = false
        sync.stop()
        update { $0.end(); return [] }
        pictures.clear()
    }

    private func reload() async { if let result = landed(await sync.read()) { send(.loaded(result)) } }

    private func landed(_ read: Result<OverviewModel, Error>) -> OverviewModel? {
        switch read {
        case .success(let result): error = nil; return result
        case .failure(let failure): error = "Load error: \(failure.localizedDescription)"; return nil
        }
    }

    func open(_ summon: Summon) async -> Bool {
        endVisit()
        pictures.prepare()
        await reload()
        update { $0.summoned(summon) }
        if visit.visible { await pictures.measure(visit.model.workspaces.flatMap(\.windows).map(\.windowId)) }
        following = visit.visible
        return visit.visible
    }

    func capturePreviews() async {
        let scene = scene
        await pictures.take(scene.cards.map { $0.tiles.map(\.window.windowId) }, sizes: scene.pictureSizes(scale: screen.scale))
    }

    func startListening() {
        sync.listen({ event in
            if case .focusChanged(let id?, _) = event { self.update { $0.noteFocus(id); return [] } }
            if self.following { self.send(.event(event)) }
        }, resumed: { if self.following { await self.reload() } })
    }

    private func requestRefresh() {
        sync.refresh { read, again in
            guard let result = self.landed(read) else { return }
            self.send(.loaded(result))
            await self.pictures.settle(result.workspaces.flatMap(\.windows).map(\.windowId))
            guard again else { return }
            let taken = await self.retakePictures()
            guard !taken.isEmpty else { return }
            Task {
                try? await Task.sleep(for: Self.repaintedAfter)
                await self.pictures.shoot(taken)
            }
        }
    }
}
