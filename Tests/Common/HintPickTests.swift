import Testing
@testable import Common

@Suite("The hint as a picker: a ring over the mode's keys")
struct HintPickTests {
    private let keys = (1...13).map { KeyBinding(mode: "apps", keys: "k\($0)", command: "open \($0)") }

    @Test("↓ and ↑ step along the column and on into the next, around the ends; ← and → keep the row across the columns, the last column's shorter end held")
    func ring() {
        let pick = HintPick(keys, marked: "k1")
        #expect(pick.columns == 2 && pick.perColumn == 7)
        #expect(pick.moved(.row(1)).marked == "k2" && pick.moved(.row(-1)).marked == "k13" && pick.moved(.row(1)).moved(.row(6)).marked == "k8")
        #expect(pick.moved(.window(1)).marked == "k8" && pick.moved(.window(1)).moved(.window(1)).marked == "k1" && pick.moved(.window(-1)).marked == "k8")
        #expect(HintPick(keys, marked: "k7").moved(.window(1)).marked == "k13" && HintPick(keys).moved(.row(1)).marked == "k1")
        #expect(pick.moved(.next) == pick && HintPick().moved(.row(1)) == HintPick())
    }

    @Test("an arrow marks, Enter picks the marked key and nothing with none marked, Escape closes, a letter is nothing")
    func pressed() {
        let pick = HintPick(keys, marked: "k3")
        #expect(pick.key(.move(.row(1))) == .marked(pick.marking("k4")))
        #expect(pick.key(.enter) == .picked(keys[2]) && pick.marking(nil).key(.enter) == .nothing)
        #expect(pick.key(.escape) == .closed && pick.key(.character("a")) == .nothing)
    }

    @Test("a mode that binds an arrow or enter keeps them: the hint takes no keys there; one that leaves them free is picked in")
    func takesKeys() {
        #expect(HintPick(keys).takesKeys)
        #expect(!HintPick(keys + [KeyBinding(mode: "window", keys: "left", command: "move left")]).takesKeys)
        #expect(!HintPick([KeyBinding(mode: "window", keys: "enter", command: "mode main")]).takesKeys)
        #expect(HintPick([KeyBinding(mode: "window", keys: "shift-left", command: "resize width +200")]).takesKeys)
    }

    @Test("a re-read keeps the mark by its key; a key that went loses it, and a ring is given to the first key only when asked")
    func reloaded() {
        let pick = HintPick(keys, marked: "k3")
        #expect(pick.reloaded(keys.reversed(), ringed: false).marked == "k3")
        #expect(pick.reloaded(Array(keys.dropFirst(5)), ringed: true).marked == "k6")
        #expect(pick.reloaded(Array(keys.dropFirst(5)), ringed: false).marked == nil)
        #expect(HintPick(keys).reloaded(keys, ringed: true).marked == "k1" && HintPick(keys).reloaded(keys, ringed: false).marked == nil)
    }
}
