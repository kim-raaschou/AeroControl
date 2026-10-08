import Foundation
import Testing
@testable import Common

// MARK: - b-argv-pins — the exact wire form of the read/subscribe commands. The format
// strings are derived from the decoders' coding keys, so these also pin that derivation
// against the spelling AeroSpace actually answers to.

@Suite("AerospaceCommand argv (list & subscribe)")
struct AerospaceCommandArgvTests {
    @Test("list-windows argv is pinned")
    func listWindows() {
        #expect(AerospaceCommand.listWindows() == [
            "list-windows", "--all", "--json", "--format",
            "%{window-id} %{app-name} %{app-bundle-id} %{window-title} %{workspace} %{window-parent-container-layout} %{window-is-fullscreen}",
        ])
    }

    @Test("list-windows with layout rects is the same read plus %{window-layout-rect}, the variable of the owner's AeroSpace branch")
    func listWindowsWithLayoutRects() {
        let plain = AerospaceCommand.listWindows()
        let rects = AerospaceCommand.listWindows(layoutRects: true)
        #expect(rects.dropLast() == plain.dropLast())
        #expect(rects.last == plain.last! + " %{window-layout-rect}")
        #expect(AerospaceCommand.listWindows(layoutRects: false) == plain)
    }

    @Test("list-workspaces argv is pinned")
    func listWorkspaces() {
        #expect(AerospaceCommand.listWorkspaces == [
            "list-workspaces", "--monitor", "all", "--json", "--format",
            "%{workspace} %{monitor-id} %{monitor-name} %{monitor-appkit-nsscreen-screens-id} %{workspace-root-container-layout} %{workspace-is-visible}",
        ])
    }

    @Test("subscribe argv is pinned")
    func subscribe() {
        #expect(AerospaceCommand.subscribe == ["subscribe", "--all", "--no-send-initial"])
    }
}

// MARK: - the event stream is a doorbell
//
// AeroSpace 0.21.3 emits exactly six event names, and is silent about window close, app
// quit, `close --window-id`, a quiet `move-node-to-workspace`, every layout change,
// fullscreen, move and resize. A reload is therefore mandatory whatever an event says, so
// events other than focus carry nothing we take, only the name is read. There is no targeted read to narrow it
// with either: `list-windows` has no `--window-id` filter, and the ~2.2 ms per-command
// floor means the narrowest available filter saves 0.5 ms out of 3.5.

@Suite("AerospaceEvent.parse")
struct AerospaceEventParseTests {
    @Test("a focus change carries the window and the workspace; every other name about windows means: read again; anything else is no event", arguments: [
        (#"{"_event":"focus-changed","windowId":42,"workspace":"2"}"#, AerospaceEvent?.some(.focusChanged(windowId: 42, workspace: "2"))),
        (#"{"_event":"focus-changed","workspace":"7"}"#, .focusChanged(windowId: nil, workspace: "7")),   // an empty workspace
        (#"{"_event":"focused-workspace-changed","prevWorkspace":"1","workspace":"2"}"#, .changed),
        (#"{"_event":"focused-monitor-changed","monitorId":1,"workspace":"2"}"#, .changed),
        (#"{"_event":"window-detected","appBundleId":"com.apple.finder","appName":"Finder","windowId":511,"workspace":"2"}"#, .changed),
        (#"{"_event":"window-detected"}"#, .changed),                        // no payload at all
        (#"{"_event":"binding-triggered","binding":"cmd-ctrl-alt-left","mode":"main"}"#, .changed),
        (#"{"_event":"mode-changed","mode":"resize"}"#, nil),                 // moves no window
        (#"{"_event":"some-future-event","workspace":"1"}"#, nil),
        // Stock AeroSpace emits no close event; the overview learns about closes from the
        // reload it does anyway. If upstream ever adds one, it lands here as a doorbell.
        (#"{"_event":"window-closed","windowId":7}"#, nil),
        ("not json", nil), ("", nil), (#"{"windowId":42,"workspace":"1"}"#, nil),
    ] as [(String, AerospaceEvent?)])
    func parse(json: String, expected: AerospaceEvent?) {
        #expect(AerospaceEvent.parse(json) == expected)
    }
}
