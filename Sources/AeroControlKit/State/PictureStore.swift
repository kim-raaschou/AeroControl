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
    private var grouping: [[Int]] = []

    func take(_ ids: [Int], cards: [[Int]], at size: CGSize) async {
        (captureSize, grouping) = (size, cards)
        let generation = generation, wanted = Set(ids)
        var waiting = cards.map { $0.filter(wanted.contains) }.filter { !$0.isEmpty }
        await bridge.windowPreviews(windowIds: ids, maxSize: size) { [weak self] id, image in
            guard let self, generation == self.generation else { return }
            self.arriving[id] = image
            while let card = waiting.first, card.allSatisfy({ self.arriving[$0] != nil }) {
                self.land(waiting.removeFirst())
            }
        }
        for card in waiting where generation == self.generation { land(card) }
        await landing?.value
    }

    private var arriving: [Int: NSImage] = [:]
    static let cardEvery: Duration = .milliseconds(25)
    private var queued: [[Int]] = []
    private var landing: Task<Void, Never>?

    private func land(_ card: [Int]) {
        queued.append(card)
        guard landing == nil else { return }
        let generation = generation
        landing = Task { [weak self] in
            while let self, generation == self.generation {
                guard !self.queued.isEmpty else { self.landing = nil; return }
                let card = Set(self.queued.removeFirst())
                let landed = self.arriving.filter { card.contains($0.key) }
                guard !landed.isEmpty else { continue }
                self.replace(landed)
                for id in landed.keys { self.arriving[id] = nil }
                try? await Task.sleep(for: Self.cardEvery)
            }
        }
    }

    func replace(_ pictures: [Int: NSImage]) {
        pictures.keys.forEach { PictureResampler.forget(previews[$0]) }
        previews.merge(pictures) { $1 }
    }

    public func want(_ id: Int, pixels: CGSize) {
        func covers(_ size: CGSize?) -> Bool { size.map { $0.width >= pixels.width * 0.95 && $0.height >= pixels.height * 0.95 } ?? false }
        guard previews[id] != nil, !covers(previews[id]?.size), !covers(asked[id]) else { return }
        wanted[id] = pixels
        guard sharpenTask == nil else { return }
        let generation = generation
        sharpenTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled, let self, generation == self.generation else { return }
            let wanted = self.wanted
            self.wanted = [:]
            self.sharpenTask = nil
            self.asked.merge(wanted) { $1 }
            let size = CGSize(width: wanted.values.map(\.width).max() ?? 0, height: wanted.values.map(\.height).max() ?? 0)
            await self.take(Array(wanted.keys).sorted(), cards: self.grouping, at: size)
        }
    }
    private var wanted: [Int: CGSize] = [:]
    private var asked: [Int: CGSize] = [:]
    private var sharpenTask: Task<Void, Never>?

    func clear() {
        generation += 1
        for task in [sharpenTask, landing] { task?.cancel() }
        (sharpenTask, landing, captureSize) = (nil, nil, nil)
        (queued, grouping, wanted, asked, arriving, previews, sizes) = ([], [], [:], [:], [:], [:], [:])
        PictureResampler.forget()
    }

    static let settleEvery: Duration = .milliseconds(50)
    static let settleWithin: Duration = .seconds(1)

    func settled(_ ids: [Int], shown: [WorkspaceInfo]) async -> ([Int: CGSize]?, [Int: NSImage]) {
        guard let size = captureSize else { return (nil, [:]) }
        let deadline = ContinuousClock.now + Self.settleWithin
        var sizes = await bridge.previewSizes(windowIds: ids)
        while ContinuousClock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: Self.settleEvery)
            let again = await bridge.previewSizes(windowIds: ids)
            if again == sizes { break }
            sizes = again
        }
        guard !Task.isCancelled else { return (nil, [:]) }
        let stale = AeroControlLayout.stale(workspaces: shown, pictures: previews.mapValues(\.size), sizes: sizes)
        var pictures: [Int: NSImage] = [:]
        if !stale.isEmpty { await bridge.windowPreviews(windowIds: stale, maxSize: size) { pictures[$0] = $1 } }
        return (sizes, pictures)
    }
}
