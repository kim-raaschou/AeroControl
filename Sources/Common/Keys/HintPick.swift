import Foundation

public struct HintPick: Equatable, Sendable {
    public enum Outcome: Equatable, Sendable { case marked(HintPick), picked(KeyBinding), closed, nothing }
    private static let keysItNeeds: Set<String> = ["up", "down", "left", "right", "enter"]

    public let bindings: [KeyBinding]
    public let marked: String?
    public let columnsAtLeast: Int

    public init(_ bindings: [KeyBinding] = [], marked: String? = nil, columnsAtLeast: Int = 1) {
        (self.bindings, self.marked, self.columnsAtLeast) = (bindings, marked, columnsAtLeast)
    }

    public var rows: [KeyBinding] { bindings.filter { $0.does != "mode main" } }
    public var back: [KeyBinding] { bindings.filter { $0.does == "mode main" } }
    public var columns: Int { max(columnsAtLeast, (rows.count + 11) / 12) }
    public var widestChord: String { rows.map(\.chord).max { $0.count < $1.count } ?? "" }
    public var perColumn: Int { max(1, (rows.count + columns - 1) / columns) }
    public var takesKeys: Bool { !bindings.contains { Self.keysItNeeds.contains($0.keys) } }
    public var chosen: KeyBinding? { rows.first { $0.keys == marked } }

    public func reloaded(_ bindings: [KeyBinding], ringed: Bool, columnsAtLeast: Int = 1) -> HintPick {
        let new = HintPick(bindings, marked: marked, columnsAtLeast: columnsAtLeast)
        return new.chosen != nil ? new : new.marking(ringed ? new.rows.first?.keys : nil)
    }

    public func marking(_ keys: String?) -> HintPick { HintPick(bindings, marked: keys, columnsAtLeast: columnsAtLeast) }

    public func moved(_ move: StripMove) -> HintPick {
        let rows = rows, at = chosen.flatMap { rows.firstIndex(of: $0) } ?? -1, to: Int?
        switch move {
        case .row(let d): to = Strip.step(at, count: rows.count, by: d)
        case .window(let d): to = Strip.step(max(at, 0) / perColumn, count: columns, by: d).map { min($0 * perColumn + max(at, 0) % perColumn, rows.count - 1) }
        default: to = nil
        }
        return to.map { HintPick(bindings, marked: rows[$0].keys, columnsAtLeast: columnsAtLeast) } ?? self
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
