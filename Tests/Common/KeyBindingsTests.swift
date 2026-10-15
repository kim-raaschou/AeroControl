import Foundation
import Testing
@testable import Common

@Suite("AeroSpace's keys, as its config tells them")
struct KeyBindingsTests {
    private let json = #"{"main":{"binding":{"cmd-ctrl-alt-10":"workspace 10","cmd-ctrl-alt-2":"workspace 2","cmd-ctrl-alt-shift-left":"move left","cmd-alt-h":""}},"apps":{"binding":{"a":"exec-and-forget  open \"aerocontrol://app-id=company.thebrowser.Browser\"; mode main","f12":"exec-and-forget  open -b \"com.apple.MobileSMS\"; mode main","esc":"mode main"}},"layout":{"binding":{"t":"layout tiling; mode main"}}}"#

    @Test("modes come main first, then by name; keys in the order a person counts")
    func order() throws {
        let keys = try parseBindings(json: json)
        #expect(keys.map(\.mode) == ["main", "main", "main", "main", "apps", "apps", "apps", "layout"])
        #expect(keys.filter { $0.mode == "main" }.map(\.keys) == ["cmd-alt-h", "cmd-ctrl-alt-2", "cmd-ctrl-alt-10", "cmd-ctrl-alt-shift-left"])
    }

    @Test("a key reads as its chord: the modifiers in the Mac's order, arrows as arrows")
    func chord() {
        #expect(KeyBinding(mode: "main", keys: "cmd-ctrl-alt-shift-left", command: "").chord == "⌃⌥⇧⌘ ←")
        #expect(KeyBinding(mode: "apps", keys: "a", command: "").chord == "a")
    }

    @Test("a command reads plainly: an app key names its app, opened by AeroControl's strip or by open; exec-and-forget, the way back to main and --flags left out, a flag's value with it")
    func does() throws {
        let keys = try parseBindings(json: json)
        let arc = try #require(keys.first { $0.keys == "a" }), sms = try #require(keys.first { $0.keys == "f12" }), tiling = try #require(keys.first { $0.keys == "t" })
        #expect(arc.app == "company.thebrowser.Browser" && sms.app == "com.apple.MobileSMS")
        #expect(tiling.app == nil && tiling.does == "layout tiling")
        #expect(KeyBinding(mode: "main", keys: "cmd-alt-3", command: "move-node-to-workspace 3 --focus-follows-window").does == "move-node-to-workspace 3")
        #expect(KeyBinding(mode: "window", keys: "down", command: "focus down --boundaries-action wrap-around-the-workspace").does == "focus down")
        #expect(KeyBinding(mode: "main", keys: "cmd-n", command: "workspace --wrap-around next").does == "workspace next")
    }
}
