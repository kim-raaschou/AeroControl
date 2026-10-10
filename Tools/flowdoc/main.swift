// Writes docs/flow.html by running the rules: every table and every branch label below is the
// answer the real functions in Common gave, not a sentence someone wrote about them. The prose
// between the tables is the only hand-written part, and it says only what cannot be run here
// (the order the host does things in, which lives in OverlayWindowManager).
//
//   make flow            regenerate docs/flow.html
//   make flow-check      fail when the committed page is stale (CI runs this)

import Foundation
import Common

// MARK: - A fixture: the windows the rules are run against

func w(_ id: Int, _ app: String, _ title: String = "") -> WindowInfo { WindowInfo(windowId: id, appName: app, bundleId: "com.\(app.lowercased())", title: title) }
let model = OverviewModel(workspaces: [
    WorkspaceInfo(name: "1", windows: [w(1, "A", "first"), w(2, "A", "second"), w(3, "B")]),
    WorkspaceInfo(name: "2", windows: [w(4, "C", "first"), w(5, "C", "second"), w(6, "D"), w(7, "D")]),
    WorkspaceInfo(name: "3", windows: [w(8, "A", "third"), w(9, "B")]),
], focusedWindowId: 1, focusedWorkspace: "1")

// MARK: - HTML

var out = ""
@MainActor func h(_ level: Int, _ text: String, id: String? = nil) { out += "<h\(level)\(id.map { " id=\"\($0)\"" } ?? "")>\(text)</h\(level)>\n" }
@MainActor func p(_ text: String) { out += "<p>\(text)</p>\n" }
func esc(_ s: String) -> String { s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
func code(_ s: String) -> String { "<code>\(esc(s))</code>" }
@MainActor func table(_ head: [String], _ rows: [[String]]) {
    out += "<table><tr>" + head.map { "<th>\($0)</th>" }.joined() + "</tr>\n"
    for r in rows { out += "<tr>" + r.map { "<td>\($0)</td>" }.joined() + "</tr>\n" }
    out += "</table>\n"
}
@MainActor func mermaid(_ body: String) { out += "<pre class=\"mermaid\">\n\(body)\n</pre>\n" }
func label(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "'") }

func describe(_ r: AppRef) -> String {
    switch r {
    case .bundleId(let id): return "the app with bundle id \(id)"
    case .name(let n): return "the app named \(n)"
    }
}
func describe(_ k: FilterKey?) -> String {
    guard let k else { return "—" }
    switch k {
    case .character(let c): return "character \(code(String(c)))"
    case .commandKey(let n): return "⌘\(FilterKey.windowKeys[n - 1])"
    default: return "\(k)"
    }
}
func describe(_ e: Visit.Effect) -> String {
    switch e {
    case .refresh: return "read AeroSpace again"
    case .run(let actions, let thenRead):
        return "run " + actions.map { code(AerospaceCommand.argv(for: $0).joined(separator: " ")) }.joined(separator: ", then ")
            + (thenRead ? ", then read AeroSpace again" : "")
    case .host(let h): return describe(h)
    }
}
func describe(_ h: Visit.Host) -> String {
    switch h {
    case .show(let s): return "show the overview for \(s)"
    case .hide: return "close"
    case .activate(let b): return "give \(b) the keyboard"
    case .quit(let b): return "quit \(b)"
    case .launch(let ref): return "start \(describe(ref)), or bring it forward; no such app: the strip's lane says so"
    case .rebuild: return "build the window again"
    case .capture: return "take the pictures again, at the size of what is showing"
    }
}
func describe(_ s: Strip?) -> String {
    guard let s else { return "no strip" }
    return "\(s.app ?? "the map") · marked \(s.marked.map(String.init) ?? "–") · centre \(s.centre.map(String.init) ?? "–")"
}

@MainActor func visit(_ m: OverviewModel) -> Visit {
    var v = Visit()
    _ = v.apply(.loaded(OverviewResult(workspaces: m.workspaces, focus: Focus(windowId: m.focusedWindowId, workspace: m.focusedWorkspace))))
    return v
}
func drawn(_ v: Visit) -> [GridWalk.Card] { OverviewScene(v, error: nil, available: CGSize(width: 1600, height: 1000), screens: [:], sizes: [:]).grid }
@MainActor func up(_ m: OverviewModel, _ s: Summon) -> (Visit, [Visit.Effect]) {
    var v = visit(m)
    _ = v.summon(s, drawn: [])
    let effects = v.summoned(s)
    return (v, effects)
}
func outcome(_ v: Visit, _ effects: [Visit.Effect]) -> String {
    let parts = (v.visible ? v.strip.map { ["the strip, marked on window \($0.marked.map(String.init) ?? "–")"] } ?? [] : []) + effects.map(describe)
    return parts.isEmpty ? "nothing" : parts.joined(separator: " · ")
}
func pressed(_ start: Visit, _ k: FilterKey) -> String {
    var v = start
    let (taken, effects) = v.key(k, drawn: drawn(v))
    guard taken else { return k == .escape ? "the window closes" : "nothing" }
    var parts = effects.map(describe)
    if v.help != start.help { parts.insert(v.help ? "show the keys" : "hide the keys", at: 0) }
    if v.query != start.query { parts.insert(v.query.isEmpty ? "clear the query" : "query becomes \(code(v.query))", at: 0) }
    if v.visible, v.marking != start.marking { parts.insert("mark window \(v.marking?.marked.map(String.init) ?? "–")", at: 0) }
    return parts.isEmpty ? "nothing" : parts.joined(separator: " · ")
}

// MARK: - 1. A link

h(1, "The map, the links and the strip")
p("Generated by <code>make flow</code> from <code>Tools/flowdoc/main.swift</code>: every table and branch below is what the functions in <code>Sources/Common</code> answered when run against a fixture of three workspaces with four apps, A to D (A ×3, B ×2, C ×2, D ×2; window 1, app A, has the focus). Change a rule and the page changes; CI fails when it is stale. The order the host does things in is the one thing written by hand, and it says where to look.")

h(2, "1. A link arrives", id: "link")
p("AeroSpace opens a URL; <code>Summon(url)</code> reads it. Which key you bind is yours; AeroControl only sees the URL.")
table(["URL", "Summon"], [
    "aerocontrol://workspaces", "aerocontrol://app-id=com.c", "aerocontrol://app-id=Com.C", "aerocontrol://app-name=C", "aerocontrol://app-name=Two%20Words", "aerocontrol://com.c", "aerocontrol://anything-else", "aerocontrol://",
].map { [code($0), code("\(Summon(URL(string: $0)!))")] })

p("For an app, <code>Visit.summoned</code> settles it from the windows the app has. Run against the fixture:")
struct Case { let title: String; let app: AppRef; let model: OverviewModel }
@MainActor func focused(_ id: Int) -> OverviewModel { OverviewModel(workspaces: model.workspaces, focusedWindowId: id, focusedWorkspace: "1") }
let cases = [
    Case(title: "no window of the app (E)", app: .bundleId("com.e"), model: model),
    Case(title: "one window: B on workspace 1 only", app: .bundleId("com.b"), model: OverviewModel(workspaces: [model.workspaces[0]], focusedWindowId: 1, focusedWorkspace: "1")),
    Case(title: "two windows, you are in one: C, focus on window 4", app: .bundleId("com.c"), model: focused(4)),
    Case(title: "two windows, from elsewhere: C, focus on A", app: .bundleId("com.c"), model: focused(1)),
    Case(title: "three windows, you are in one: A, focus on window 1", app: .bundleId("com.a"), model: focused(1)),
    Case(title: "three windows, from elsewhere: A, focus on D", app: .bundleId("com.a"), model: focused(6)),
    Case(title: "the same, by name: app-name=A", app: .name("A"), model: focused(6)),
    Case(title: "by a name no window has: app-name=Z", app: .name("Z"), model: focused(6)),
]
let on = cases.map { c in let (v, effects) = up(c.model, .app(c.app)); return outcome(v, effects) }
table(["Case", "What the key does"], zip(cases, on).map { [$0.title, $1] })
mermaid("""
flowchart TD
  L["open aerocontrol://…"] --> H{"which link?"}
  H -- "workspaces, or anything else" --> MAP["the map: every workspace,<br/>ring on AeroSpace's focus<br/>→ section 4"]
  click MAP "#map"
  H -- "app-id= · app-name=" --> APP["that app, by bundle id or by name"]
  APP --> N{"windows of the app"}
  N -- "none" --> A0["\(label((on[0])))"]
  N -- "one" --> A1["\(label((on[1])))"]
  N -- "two, you in one" --> A2["\(label((on[2])))"]
  N -- "otherwise" --> A4["\(label((on[4])))<br/>→ section 3, the strip"]
  click A4 "#strip"
""")
p("Two leaves continue: the map in <a href=\"#map\">section 4</a>, and the strip, the one case that needs you, in <a href=\"#strip\">section 3</a>. Everything else is settled and done here.")
p("Where the strip opens: <code>AppStripModel.start</code>. On the app's window you used last other than the one you are in, as ⌘` goes back to it; knowing none, on the window after yours, or the first.")
table(["You are in", "The app's windows", "Used last", "Opens on"], [
    ["window 2", "[1, 2, 8]", "2, then 1", "\(AppStripModel.start(origin: 2, ids: [1, 2, 8], recent: [2, 1]) ?? 0)"],
    ["window 2", "[1, 2, 8]", "none known", "\(AppStripModel.start(origin: 2, ids: [1, 2, 8]) ?? 0)"],
    ["window 8 (the last)", "[1, 2, 8]", "none known", "\(AppStripModel.start(origin: 8, ids: [1, 2, 8]) ?? 0)"],
    ["another app", "[1, 2, 8]", "8, then 2", "\(AppStripModel.start(origin: 6, ids: [1, 2, 8], recent: [8, 2]) ?? 0)"],
    ["another app", "[1, 2, 8]", "none known", "\(AppStripModel.start(origin: 6, ids: [1, 2, 8]) ?? 0)"],
])

h(2, "2. The link again, while the overview is up", id: "again")
p("<code>Visit.summon</code> while the overview is up, given what is showing:")
let showing: [Summon] = [.map, .app(.bundleId("com.a"))]
table(["Link", "the map is up", "A's strip is up"], [
    ("workspaces", Summon.map), ("app-id=com.a", Summon.app(.bundleId("com.a"))), ("app-name=A", Summon.app(.name("A"))), ("app-id=com.c", Summon.app(.bundleId("com.c"))),
].map { name, s in [code(name)] + showing.map { first in var (v, _) = up(model, first); let effects = v.summon(s, drawn: drawn(v)); return outcome(v, effects) } })
p("The host carries the effects out (<code>OverlayWindowManager.perform</code>). Another app's link runs section 1 again in place, so the strip takes over from whatever was showing.")

// MARK: - 3. The strip

h(2, "3. The strip", id: "strip")
p("This is where the last leaf of <a href=\"#link\">section 1</a> lands: an app's key, pressed with windows to choose between. The strip is a value in Common (<code>Strip</code>) with four transitions; the store holds the current one. Keys through <code>Visit.key</code>, run against A's strip of windows [1, 2, 8], opened from window 1 and marked on 2:")
let (stripVisit, _) = up(model, .app(.bundleId("com.a")))
let stripKeys: [FilterKey] = [.move(.window(1)), .move(.window(-1)), .move(.row(1)), .move(.workspace(1)), .enter, .escape, .commandKey(1), .commandKey(3), .commandKey(4), .character("a"), .backspace]
table(["Key", "Does"], stripKeys.compactMap { k in
    let does = pressed(stripVisit, k)
    return does == "nothing" ? nil : [describe(k), does]
})
p("Every other key does nothing in the strip: there is no typing there, and a ⌘ key past the strip's last window (⌘4 here) is nothing. The windows' keys, ⌘1–⌘9 then ⌘a–⌘f (<code>FilterKey(command:)</code>, <code>Visit.key</code>), run against a strip of fifteen windows:")
let (fifteen, _) = up(OverviewModel(workspaces: [WorkspaceInfo(name: "1", windows: (1...15).map { w($0, "A") }), WorkspaceInfo(name: "2", windows: [w(20, "B")])], focusedWindowId: 20, focusedWorkspace: "2"), .app(.bundleId("com.a")))
table(["⌘ + character", "In a strip of fifteen windows"], ["1", "9", "a", "f", "g", "0"].map { c in
    ["⌘\(c)", FilterKey(command: c, shift: false).map { pressed(fifteen, $0) } ?? "nothing: not a window's key"]
})
p("The keys the windows carry (<code>AppStripModel.keyLabel</code>): " + (0..<17).map { AppStripModel.keyLabel($0) ?? "none" }.joined(separator: ", ") + " for the first seventeen windows.")

p("What happens to a strip of app A, opened from its window 1 (A's windows are 1, 2 and 8, on two workspaces), as each thing happens to it. Every line is the value the transition returned:")
let opened = Strip.opened("com.a", origin: 1, ids: [1, 2, 8], recent: [])
let card: (Int) -> Int? = { id in model.workspaces.firstIndex { $0.windows.contains { $0.windowId == id } } }
let stepped = opened.moved(.window(1), ids: [1, 2, 8], card: card)
let round = stepped.moved(.window(1), ids: [1, 2, 8], card: card)
/// What a transition did, in the strip's own terms: where the marking went, whether the
/// row followed it, whose strip it is now, or that it is over.
func tell(_ before: Strip, _ after: Strip?) -> String {
    guard let after else { return "the strip is over: nothing to choose" }
    var parts: [String] = []
    if after.app != before.app { parts.append("the strip is \(after.app ?? "the map")'s now") }
    if after.marked != before.marked { parts.append("the marking goes to window \(after.marked.map(String.init) ?? "none")") }
    if after.centre != before.centre { parts.append("the row centres on it") } else if after.marked != before.marked { parts.append("the row stays where it was") }
    return parts.isEmpty ? "nothing changes" : parts.joined(separator: "; ")
}
table(["What happened", "The strip"], [
    ["opened from window 1", "marked on window \(opened.marked ?? 0), the one after yours; the row centred on it"],
    ["the app key again", tell(opened, stepped)],
    ["the app key again, past the last window", tell(stepped, round)],
    ["the pointer moves onto window 8", tell(opened, opened.marking(8))],
    ["window 2, the marked one, closes", tell(opened, opened.kept(before: [1, 2, 8], after: [1, 8]))],
    ["AeroSpace moves the focus to A's window 8", tell(opened, opened.following(w(8, "A")))],
    ["AeroSpace moves the focus to C's window 4; C has two", tell(opened, opened.following(w(4, "C")))],
    ["AeroSpace moves the focus to an empty workspace", tell(opened, opened.following(nil))],
])
mermaid("""
flowchart TD
  OPEN["opened: \(label(describe(opened)))"] --> UP(("up"))
  UP -- "← → ↑ ↓ · ⌘ and an arrow · a workspace's name · the app's key again" --> STEP["moved: marking and centre move;<br/>the row slides to keep the card in view"]
  UP -- "pointer onto a window" --> MARK["marking: marking moves, centre stays"]
  UP -- "⌘1–⌘9, ⌘a–⌘f · Enter · click" --> COMMIT["focus that window · close"]
  UP -- "Escape · backdrop" --> CANCEL["close"]
  UP -- "⌘W · ⌘Q" --> GONE["the marked window closes · its app quits;<br/>the marking passes on"]
  UP -- "AeroSpace: focus moved" --> WHERE{"to a window of"}
  WHERE -- "this app" --> UP
  WHERE -- "anywhere else: another app, an empty workspace" --> OVER["over: chosen with AeroSpace · close"]
  UP -- "a read changed the windows" --> KEPT["kept: marking stays, or passes<br/>to a closed one's successor"]
  STEP --> UP
  MARK --> UP
  KEPT --> UP
""")
p("The line under the cards (<code>AppStripModel.summary</code>), after the app's name, for A's three windows marked on 2: "
  + code(esc(AppStripModel.summary(model.windowsInGridOrder.filter { $0.window.bundleId == "com.a" }, marked: 2)))
  + ". The marked window's key is on its card; pointing at a window marks it, so its title is read here.")

// MARK: - 4. The map

h(2, "4. The map", id: "map")
p("Hand-written, from <code>OverlayWindowManager.show</code>: read everything once (<code>reload</code>: list-windows with layout rects, list-workspaces, the focus), decide the summon (<a href=\"#link\">section 1</a>), measure every window's size, follow AeroSpace's events, build the window and reveal it after 120 ms, then take the pictures, which land card by card. While it is up, every AeroSpace event goes through <code>OverviewStore.send</code> into <code>Visit.apply</code>:")
let inputs: [(String, Visit.Input)] = [
    ("event: focus-changed to window 5 on workspace 2", .event(.focusChanged(windowId: 5, workspace: "2"))),
    ("event: anything else AeroSpace reports", .event(.changed)),
    ("a read came back", .loaded(OverviewResult(workspaces: [model.workspaces[0]], focus: Focus(windowId: 2, workspace: "1")))),
    ("action: focus window 5", .action(.focusWindow(5))),
    ("action: focus workspace 2", .action(.focusWorkspace("2"))),
    ("action: move window 3 to workspace 2", .action(.moveWindow(windowId: 3, toWorkspace: "2"))),
    ("action: close window 3", .action(.closeWindow(3))),
    ("action: merge workspace 1 into 2", .action(.mergeWorkspace(source: "1", into: "2"))),
]
table(["Input", "Model after", "Effects"], inputs.map { name, input in
    var v = visit(model)
    let effects = v.apply(input), new = v.model
    let change = new == model ? "unchanged" : "focus → window \(new.focusedWindowId) on workspace \(new.focusedWorkspace)" + (new.workspaces != model.workspaces ? ", workspaces replaced" : "")
    return [name, change, effects.isEmpty ? "—" : effects.map(describe).joined(separator: "<br/>")]
})
p("What AeroSpace's lines mean to us (<code>AerospaceEvent.parse</code>):")
table(["Line", "Event"], [
    #"{"_event":"focus-changed","windowId":5,"workspace":"2"}"#, #"{"_event":"focus-changed","workspace":"3"}"#,
    #"{"_event":"focused-workspace-changed","workspace":"2"}"#, #"{"_event":"focused-monitor-changed","monitorId":1}"#,
    #"{"_event":"window-detected","windowId":9}"#, #"{"_event":"binding-triggered","binding":"alt-h"}"#,
    #"{"_event":"mode-changed","mode":"resize"}"#, #"{"_event":"some-future-event"}"#, "not json",
].map { [code($0), AerospaceEvent.parse($0).map { "\($0)" } ?? "not an event: ignored"] })

p("Keys on the map (<code>FilterKey(keyCode:)</code>, then <code>Visit.key</code>). The ring is AeroSpace's focused window, window 1, until a query has a match; with the query <code>d</code> the first match is app D, window 6:")
let keys: [(String, UInt16, Bool, String?)] = [
    ("Escape", 53, false, nil), ("Backspace", 51, false, nil), ("Enter", 36, false, "\r"), ("Tab", 48, false, "\t"),
    ("→", 124, false, nil), ("←", 123, false, nil), ("↑", 126, false, "\u{F700}"), ("↓", 125, false, "\u{F701}"), ("Home", 115, false, nil),
    ("a", 0, false, "a"), ("2", 19, false, "2"), ("space", 49, false, " "), ("F1", 122, false, "\u{F704}"),
]
let onMap = visit(model)
var typed = onMap
_ = typed.key(.character("d"), drawn: drawn(typed))
let mapRows: [[String]] = keys.compactMap { name, kc, _, chars in
    guard let k = FilterKey(keyCode: kc, characters: chars) else { return nil }
    let row = [name, describe(k), pressed(onMap, k), pressed(typed, k)]
    return row[2] == "nothing" && row[3] == "nothing" ? nil : row
}
table(["Key", "FilterKey", "No query, ring on 1", "Query <code>d</code>, ring on 6"], mapRows)
p("The arrows, ⌘ and an arrow, and pointing move the ring on the map as they move the marking in the strip (<code>Strip.moved</code>, <code>GridWalk</code>): until a key or the pointer moves it the ring is AeroSpace's focus, and AeroSpace's focus stays on screen as the thin outline. Tab, Home, End and the function keys do nothing.")
p("⇧⌘ and a workspace's name (<code>FilterKey.moveToWorkspace</code>, 0 the tenth) moves the window under the ring to that workspace, on the map and in the strip, and the overview stays up. Two ⌘ keys act on the window under the ring, as they would without the overview, taken before the filter sees them (<code>Visit.commandTarget</code>, <code>OverviewWindow.performKeyEquivalent</code>): ⌘W closes it, as its × does, and ⌘Q quits its app, on the map and in the strip, and the overview stays up; with no window under the ring (an empty workspace's card, a notice) ⌘W does nothing. Every other ⌘ key does nothing.")

h(2, "5. One way out", id: "out")
p("Hand-written, from <code>Visit.apply</code> and <code>OverlayWindowManager.perform</code>: a focus action (focus window, focus workspace) and a strip that is over (<code>Strip.following</code> returned nil) both make <code>Visit.apply</code> answer <code>hide</code>. The host hides the window and, unless the focus just moved there, gives the focused app the keyboard. Escape and a click on the backdrop end the same way, through <code>Visit.hide</code>.")

// MARK: - write

let page = """
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AeroControl: the map, the links and the strip</title>
<style>
  :root { --bg: #fff; --fg: #1d1d1f; --muted: #6e6e73; --line: #e5e5ea; --card: #f5f5f7; }
  @media (prefers-color-scheme: dark) { :root { --bg: #111114; --fg: #e8e8ed; --muted: #9a9aa3; --line: #2a2a30; --card: #1a1a1f; } }
  body { font: 15px/1.55 -apple-system, system-ui, sans-serif; color: var(--fg); background: var(--bg); max-width: 1180px; margin: 2.5rem auto; padding: 0 1.25rem; }
  h1 { font-size: 26px; font-weight: 600; margin: 0 0 .5rem; }
  h2 { font-size: 20px; font-weight: 600; margin: 2.5rem 0 .5rem; border-top: 1px solid var(--line); padding-top: 1.5rem; }
  p { margin: .5rem 0 1rem; }
  code { font: 13px ui-monospace, SFMono-Regular, Menlo, monospace; background: var(--card); padding: 1px 5px; border-radius: 4px; }
  pre.mermaid { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 1rem; overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; margin: .75rem 0 1.25rem; }
  td, th { text-align: left; vertical-align: top; padding: 6px 10px; border-bottom: 1px solid var(--line); }
  th { color: var(--muted); font-weight: 500; }
</style></head><body>
\(out)
<script src="https://cdnjs.cloudflare.com/ajax/libs/mermaid/11.15.0/mermaid.min.js"></script>
<script>mermaid.initialize({ startOnLoad: true, theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral', securityLevel: 'loose', flowchart: { useMaxWidth: true } });</script>
</body></html>

"""
let target = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "docs/flow.html")
if CommandLine.arguments.contains("--check") {
    let current = (try? String(contentsOf: target, encoding: .utf8)) ?? ""
    if current != page { FileHandle.standardError.write("flow: docs/flow.html is stale — run make flow\n".data(using: .utf8)!); exit(1) }
    print("flow: docs/flow.html is current.")
} else {
    try page.write(to: target, atomically: true, encoding: .utf8)
    print("Wrote \(target.path)")
}
