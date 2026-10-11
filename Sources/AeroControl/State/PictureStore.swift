import AppKit
import Common

@MainActor @Observable
final class PictureStore {
    private(set) var previews: [Int: CGImage] = [:]
    private(set) var frames: [Int: CGRect] = [:]

    private let bridge: NativeApiBridge
    init(bridge: NativeApiBridge) { self.bridge = bridge }

    func icon(for bundleId: String) -> NSImage { bridge.appIcon(bundleId: bundleId) }
    func live(_ id: Int, pixels: CGSize) -> NSView { bridge.liveWindow(id, pixels: pixels) }

    private var generation = 0

    func prepare() { bridge.prepareCapture() }

    func measure(_ ids: [Int]) async {
        generation += 1
        let generation = generation
        let frames = await bridge.windowFrames(windowIds: ids)
        guard generation == self.generation else { return }
        self.frames = frames
    }

    private var boxes: [Int: CGSize]?

    func take(_ cards: [[Int]], sizes: [Int: CGSize], landed: () -> Void = {}) async {
        generation += 1
        boxes = sizes
        let generation = generation
        var waiting = cards.filter { !$0.isEmpty }, arrived: [Int: CGImage] = [:]
        await bridge.windowPreviews(cards.flatMap { $0 }, filling: sizes) { id, image in
            guard generation == self.generation else { return }
            arrived[id] = image
            while let card = waiting.first, card.allSatisfy({ arrived[$0] != nil }) {
                waiting.removeFirst()
                previews.merge(arrived.filter { card.contains($0.key) }) { $1 }
                landed()
            }
        }
        guard generation == self.generation else { return }
        previews.merge(arrived.filter { id, _ in waiting.contains { $0.contains(id) } }) { $1 }
    }

    func clear() {
        generation += 1
        (boxes, previews, frames) = (nil, [:], [:])
    }

    func settle(_ ids: [Int], sizes: [Int: CGSize], shown: [WorkspaceInfo], retake: Bool) async {
        guard boxes != nil else { return }
        let generation = generation
        let frames = await bridge.windowFrames(windowIds: ids)
        let pictured = previews.mapValues { CGSize(width: $0.width, height: $0.height) }
        let stale = retake ? AeroControlLayout.stale(workspaces: shown, pictures: pictured, sizes: frames.mapValues(\.size)) : []
        var pictures: [Int: CGImage] = [:]
        boxes?.merge(sizes.filter { stale.contains($0.key) }) { $1 }
        if !stale.isEmpty { await bridge.windowPreviews(stale, filling: sizes) { pictures[$0] = $1 } }
        guard !Task.isCancelled, generation == self.generation else { return }
        self.frames = frames
        previews.merge(pictures) { $1 }
    }

    func grow(_ sizes: [Int: CGSize]) async {
        let larger = sizes.filter { id, size in boxes?[id].map { size.width > $0.width + 1 || size.height > $0.height + 1 } ?? false }
        guard !larger.isEmpty else { return }
        boxes?.merge(larger) { $1 }
        let generation = generation
        var pictures: [Int: CGImage] = [:]
        await bridge.windowPreviews(Array(larger.keys), filling: larger) { pictures[$0] = $1 }
        guard generation == self.generation else { return }
        previews.merge(pictures) { $1 }
    }
}
