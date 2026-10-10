import AppKit
import Common

/// The pictures of the overview's windows, for one visit: their sizes measured before any
/// picture is taken, the pictures taken once and landed a card at a time, taken again sharper
/// where a tile draws one larger, taken again where a refresh left one the wrong shape, and
/// all dropped when the visit ends. The store says which windows, and which cards they are on;
/// this keeps them and talks to the bridge.
@MainActor @Observable
public final class PictureStore {
    /// Window previews, captured when the overview is summoned and dropped when it hides.
    /// They land a card at a time into a grid that is already on screen.
    public private(set) var previews: [Int: NSImage] = [:]
    /// Each window's on-screen size, known before any picture is: the grid takes its
    /// shape from these, so pictures landing later change nothing but the pictures.
    public internal(set) var sizes: [Int: CGSize] = [:]

    private let bridge: NativeApiBridge
    init(bridge: NativeApiBridge) { self.bridge = bridge }

    /// Bumped by every capture and clear so a stale capture cannot overwrite newer state.
    private(set) var generation = 0

    /// Reads every window's size — cheap, the enumeration was started with `prepare` — so
    /// the overview can be revealed with its final shape before a picture is taken.
    func measure(_ ids: [Int]) async {
        generation += 1
        let generation = generation
        let sizes = await bridge.previewSizes(windowIds: ids)
        guard generation == self.generation else { return }
        self.sizes = sizes
    }

    /// The box pictures were taken to fit, and the cards they land by, kept for re-taking a few.
    private var captureSize: CGSize?
    private var grouping: [[Int]] = []

    /// Takes these windows' pictures at `size`, landing a card's once all of its pictures and
    /// the cards' before it are in; when the capture is, the rest — a card with a window that
    /// gave no picture. Returns when all are in. A `clear()` in the meantime discards the rest.
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

    /// Pictures taken but not yet in `previews`. A card's land together once all of them are
    /// in, the cards in reading order and `cardEvery` apart: one by one, or each card as it was
    /// in, they came in all over the screen. And every picture stored redraws the whole
    /// overview — on the main thread that drew the map once per window and kept the captures
    /// still in flight from landing.
    private var arriving: [Int: NSImage] = [:]
    static let cardEvery: Duration = .milliseconds(25)
    /// Cards whose pictures are in, waiting their turn.
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

    /// New pictures over old: an old one's scaled copies go before it does (`PictureResampler.forget`).
    func replace(_ pictures: [Int: NSImage]) {
        pictures.keys.forEach { PictureResampler.forget(previews[$0]) }
        previews.merge(pictures) { $1 }
    }

    /// The pixels a tile draws a picture at, as the tiles report them; a picture taken smaller
    /// is taken again at that size, the few that need it together once the reports settle
    /// (150 ms) — a filter narrowing to one window, a workspace alone on a card. What was asked
    /// is kept, so a window too small to give more is not asked again: no loop, no clock.
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

    /// The visit ends: the pictures go, with whatever was still being taken.
    func clear() {
        generation += 1
        for task in [sharpenTask, landing] { task?.cancel() }
        (sharpenTask, landing, captureSize) = (nil, nil, nil)
        (queued, grouping, wanted, asked, arriving, previews, sizes) = ([], [], [:], [:], [:], [:], [:])
        PictureResampler.forget()
    }

    /// After a refresh the windows' sizes are read from the window server every `settleEvery`, until two reads
    /// agree or `settleWithin` has passed: apps resize after AeroSpace moves their windows, in their
    /// own time, 70–280 ms measured. Taken at fixed times, a picture caught a window halfway.
    static let settleEvery: Duration = .milliseconds(50)
    static let settleWithin: Duration = .seconds(1)

    /// The windows' sizes once they stand still, and new pictures of those `shown` whose picture
    /// no longer fits what they are drawn at (`AeroControlLayout.stale`), or that have none: the
    /// neighbours that widened into a hole, a window that appeared, a hidden workspace's slot that
    /// changed, the cards of a strip that took over another's. Nothing is stored, so a refresh cut
    /// off by the next loses nothing. Nil while the overview is hidden: `clear` has dropped the
    /// capture size.
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
        let stale = AeroControlLayout.stale(workspaces: shown, pictures: previews.mapValues(\.size), sizes: sizes)
        var pictures: [Int: NSImage] = [:]
        if !stale.isEmpty { await bridge.windowPreviews(windowIds: stale, maxSize: size) { pictures[$0] = $1 } }
        return (sizes, pictures)
    }
}
