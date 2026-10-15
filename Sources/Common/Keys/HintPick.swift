import Foundation

public struct HintPick: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable { case marked(HintPick), picked(KeyBinding), closed, nothing }
    private static let keysItNeeds: Set<String> = ["up", "down", "left", "right", "enter"]

    public let bindings: [KeyBinding]
    public let marked: String?

    public init(_ bindings: [KeyBinding] = [], marked: String? = nil) { (self.bindings, self.marked) = (bindings, marked) }

    public var columns: Int { max(1, (bindings.count + 11) / 12) }
    public var perColumn: Int { max(1, (bindings.count + columns - 1) / columns) }
    public var takesKeys: Bool { !bindings.contains { Self.keysItNeeds.contains($0.keys) } }
    public var chosen: KeyBinding? { bindings.first { $0.keys == marked } }

    public func reloaded(_ rows: [KeyBinding], ringed: Bool) -> HintPick {
        HintPick(rows, marked: rows.contains { $0.keys == marked } ? marked : ringed ? rows.first?.keys : nil)
    }

    public func marking(_ keys: String?) -> HintPick { HintPick(bindings, marked: keys) }

    public func moved(_ move: StripMove) -> HintPick {
        let at = chosen.flatMap { bindings.firstIndex(of: $0) } ?? -1, to: Int?
        switch move {
        case .row(let d): to = Strip.step(at, count: bindings.count, by: d)
        case .window(let d): to = Strip.step(max(at, 0) / perColumn, count: columns, by: d).map { min($0 * perColumn + max(at, 0) % perColumn, bindings.count - 1) }
        default: to = nil
        }
        return to.map { HintPick(bindings, marked: bindings[$0].keys) } ?? self
    }

    public func key(_ key: FilterKey) -> Outcome {
        switch key {
        case .move(let move): return .marked(moved(move))
        case .enter: return chosen.map { .picked($0) } ?? .nothing
        case .escape: return .closed
        default: return .nothing
        }
    }
}
