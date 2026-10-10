import AppKit
import Common
import Observation

@MainActor @Observable
public class OverviewStore {
    public private(set) var visit = Visit()
    public var model: OverviewModel { visit.model }
    public var strip: Strip? { visit.strip }

    private let sync: AerospaceSync
    public let pictures: PictureStore
    public private(set) var error: String?
    public var screen: (available: CGSize, frames: [Int: CGRect]) = (.zero, [:])
    public var following = false
    public var onEffect: ((Visit.Host) -> Void)?

    public var scene: OverviewScene { OverviewScene(visit, error: error, available: screen.available, screens: screen.frames, sizes: pictures.sizes) }
    var drawn: [GridWalk.Card] { scene.grid }

    public init(runner: AerospaceProcessRunner, nativeSystem: NativeApiBridge) {
        self.sync = AerospaceSync(runner: runner)
        self.pictures = PictureStore(bridge: nativeSystem)
    }

    public func update(_ body: (inout Visit) -> [Visit.Effect]) {
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

    public func send(_ input: Visit.Input) { update { $0.apply(input) } }

    @discardableResult public func handle(_ key: FilterKey) -> Bool {
        let drawn = drawn
        var taken = false
        update { visit in let (handled, effects) = visit.key(key, drawn: drawn); taken = handled; return effects }
        return taken
    }

    public func summon(_ summon: Summon) { let drawn = drawn; update { $0.summon(summon, drawn: drawn) } }
    @ObservationIgnored private var pointer: CGPoint?
    public func notePointer(_ location: CGPoint) { pointer = location }
    public func point(_ windowId: Int, at location: CGPoint) {
        guard location != pointer else { return }
        pointer = location
        update { $0.point(windowId); return [] }
    }

    public func endVisit() {
        following = false
        sync.stop()
        update { $0.end(); return [] }
        pictures.clear()
    }

    public func reload() async { if let result = landed(await sync.read()) { send(.loaded(result)) } }

    private func landed(_ read: Result<OverviewResult, Error>) -> OverviewResult? {
        switch read {
        case .success(let result): error = nil; return result
        case .failure(let failure): error = "Load error: \(failure.localizedDescription)"; return nil
        }
    }

    public func measurePreviews() async { await pictures.measure(model.workspaces.flatMap(\.windows).map(\.windowId)) }

    public func capturePreviews(maxSize: CGSize) async {
        await pictures.take(visit.shownWorkspaces.flatMap { $0.windows.map(\.windowId) },
                            cards: model.workspaces.map { $0.windows.map(\.windowId) }, at: maxSize)
    }

    public func startListening() {
        sync.listen({ event in
            if case .focusChanged(let id?, _) = event { self.update { $0.noteFocus(id); return [] } }
            if self.following { self.send(.event(event)) }
        }, resumed: { if self.following { await self.reload() } })
    }

    private func requestRefresh() {
        sync.refresh { read, again, current in
            guard let result = self.landed(read) else { return }
            self.send(.loaded(result))
            await self.pictures.settle(result.workspaces.flatMap(\.windows).map(\.windowId), shown: self.visit.shownWorkspaces, retake: again, current: current)
        }
    }
}
