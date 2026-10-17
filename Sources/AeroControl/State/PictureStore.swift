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

    func measure(_ ids: [Int]) {
        generation += 1
        let frames = bridge.windowFrames(windowIds: ids)
        (self.frames, previews) = (frames, previews.filter { id, picture in
            frames[id].map { AeroControlLayout.sameShape(CGSize(width: picture.width, height: picture.height), $0.size) } ?? false })
    }

    private var boxes: [Int: CGSize]?

    func take(_ cards: [[Int]], sizes: [Int: CGSize]) async {
        generation += 1
        boxes = sizes
        let generation = generation
        var waiting = cards.filter { !$0.isEmpty }, arrived: [Int: CGImage] = [:]
        await bridge.windowPreviews(cards.flatMap { $0 }, filling: sizes, frames: frames) { id, image in
            guard generation == self.generation else { return }
            arrived[id] = image
            while let card = waiting.first, card.allSatisfy({ arrived[$0] != nil }) {
                waiting.removeFirst()
                previews.merge(arrived.filter { card.contains($0.key) }) { $1 }
            }
        }
        guard generation == self.generation else { return }
        previews.merge(arrived.filter { id, _ in waiting.contains { $0.contains(id) } }) { $1 }
    }

    func clear() {
        generation += 1
        (boxes, frames) = (nil, [:])
    }

    func settle(_ ids: [Int]) { frames = bridge.windowFrames(windowIds: ids) }

    func retake(_ sizes: [Int: CGSize]) async -> [Int: CGSize] {
        let changed = sizes.filter { id, size in boxes.map { $0[id] != size } ?? false }
        if !changed.isEmpty { await shoot(changed) }
        return changed
    }

    func shoot(_ changed: [Int: CGSize]) async {
        let generation = generation
        var pictures: [Int: CGImage] = [:]
        await bridge.windowPreviews(Array(changed.keys), filling: changed, frames: frames) { pictures[$0] = $1 }
        guard generation == self.generation else { return }
        boxes?.merge(Task.isCancelled ? changed.filter { pictures[$0.key] != nil } : changed) { $1 }
        previews.merge(pictures) { $1 }
    }
}
