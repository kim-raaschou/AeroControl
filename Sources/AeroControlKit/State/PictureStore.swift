import AppKit
import Common

@MainActor @Observable
public final class PictureStore {
    public private(set) var previews: [Int: NSImage] = [:]
    public internal(set) var sizes: [Int: CGSize] = [:]

    private let bridge: NativeApiBridge
    init(bridge: NativeApiBridge) { self.bridge = bridge }

    public func icon(for bundleId: String) -> NSImage { bridge.appIcon(bundleId: bundleId) }
    public func live(_ id: Int, pixels: CGSize) -> NSView { bridge.liveWindow(id, pixels: pixels) }

    private(set) var generation = 0

    func measure(_ ids: [Int]) async {
        generation += 1
        let generation = generation
        let sizes = await bridge.previewSizes(windowIds: ids)
        guard generation == self.generation else { return }
        self.sizes = sizes
    }

    private var captureSize: CGSize?

    func take(_ ids: [Int], cards: [[Int]], at size: CGSize) async {
        generation += 1
        captureSize = size
        let generation = generation, wanted = Set(ids)
        var waiting = cards.map { $0.filter(wanted.contains) }.filter { !$0.isEmpty }, arrived: [Int: NSImage] = [:]
        await bridge.windowPreviews(windowIds: ids, maxSize: size) { id, image in
            guard generation == self.generation else { return }
            arrived[id] = image
            while let card = waiting.first, card.allSatisfy({ arrived[$0] != nil }) {
                waiting.removeFirst()
                replace(arrived.filter { card.contains($0.key) })
            }
        }
        guard generation == self.generation else { return }
        replace(arrived.filter { id, _ in waiting.contains { $0.contains(id) } })
    }

    func replace(_ pictures: [Int: NSImage]) {
        pictures.keys.forEach { PictureResampler.forget(previews[$0]) }
        previews.merge(pictures) { $1 }
    }

    func clear() {
        generation += 1
        (captureSize, previews, sizes) = (nil, [:], [:])
        PictureResampler.forget()
    }

    static let retakeAfter: Duration = .milliseconds(300)

    func settle(_ ids: [Int], shown: [WorkspaceInfo], current: @MainActor () -> Bool) async {
        guard let size = captureSize else { return }
        let generation = generation
        func still() -> Bool { current() && generation == self.generation }
        let sizes = await bridge.previewSizes(windowIds: ids)
        guard still() else { return }
        self.sizes = sizes
        try? await Task.sleep(for: Self.retakeAfter)
        guard still() else { return }
        let settled = await bridge.previewSizes(windowIds: ids)
        let stale = AeroControlLayout.stale(workspaces: shown, pictures: previews.mapValues(\.size), sizes: settled)
        var pictures: [Int: NSImage] = [:]
        if !stale.isEmpty { await bridge.windowPreviews(windowIds: stale, maxSize: size) { pictures[$0] = $1 } }
        guard still() else { return }
        self.sizes = settled
        replace(pictures)
    }
}
