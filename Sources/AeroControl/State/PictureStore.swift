import AppKit
import Common

@MainActor @Observable
final class PictureStore {
    private(set) var previews: [Int: NSImage] = [:]
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

    private func replace(_ pictures: [Int: NSImage]) {
        pictures.keys.forEach { PictureResampler.forget(previews[$0]) }
        previews.merge(pictures) { $1 }
    }

    func clear() {
        generation += 1
        (captureSize, previews, frames) = (nil, [:], [:])
        PictureResampler.forget()
    }

    func settle(_ ids: [Int], shown: [WorkspaceInfo], retake: Bool) async {
        guard let size = captureSize else { return }
        let generation = generation
        let frames = await bridge.windowFrames(windowIds: ids)
        let stale = retake ? AeroControlLayout.stale(workspaces: shown, pictures: previews.mapValues(\.size), sizes: frames.mapValues(\.size)) : []
        var pictures: [Int: NSImage] = [:]
        if !stale.isEmpty { await bridge.windowPreviews(windowIds: stale, maxSize: size) { pictures[$0] = $1 } }
        guard !Task.isCancelled, generation == self.generation else { return }
        self.frames = frames
        replace(pictures)
    }
}
