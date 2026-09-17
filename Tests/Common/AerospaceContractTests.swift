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
            "%{window-id} %{app-name} %{app-bundle-id} %{window-title} %{workspace} %{window-parent-container-layout}",
        ])
    }

    @Test("list-workspaces argv is pinned")
    func listWorkspaces() {
        #expect(AerospaceCommand.listWorkspaces() == [
            "list-workspaces", "--monitor", "all", "--json", "--format",
            "%{workspace} %{monitor-id} %{monitor-name}",
        ])
    }

    @Test("subscribe argv is pinned")
    func subscribe() {
        #expect(AerospaceCommand.subscribe() == ["subscribe", "--all", "--no-send-initial"])
    }
}

// MARK: - the event stream is a doorbell
//
// AeroSpace 0.21.3 emits exactly six event names, and is silent about window close, app
// quit, `close --window-id`, a quiet `move-node-to-workspace`, every layout change,
// fullscreen, move and resize. A reload is therefore mandatory whatever an event says, so
// events carry no data and only the name is read. There is no targeted read to narrow it
// with either: `list-windows` has no `--window-id` filter, and the ~2.2 ms per-command
// floor means the narrowest available filter saves 0.5 ms out of 3.5.

@Suite("AerospaceEvent.parse")
struct AerospaceEventParseTests {

    @Test("every name AeroSpace emits about windows means: read again", arguments: [
        #"{"_event":"focus-changed","windowId":1,"workspace":"2"}"#,
        #"{"_event":"focus-changed","workspace":"7"}"#,                       // empty workspace
        #"{"_event":"focused-workspace-changed","prevWorkspace":"1","workspace":"2"}"#,
        #"{"_event":"focused-monitor-changed","monitorId":1,"workspace":"2"}"#,
        #"{"_event":"window-detected","appBundleId":"com.apple.finder","appName":"Finder","windowId":511,"workspace":"2"}"#,
        #"{"_event":"window-detected"}"#,                                     // no payload at all
        #"{"_event":"binding-triggered","binding":"cmd-ctrl-alt-left","mode":"main"}"#,
    ])
    func knownNamesMeanChanged(json: String) {
        #expect(AerospaceEvent.parse(json) == .changed)
    }

    @Test("names that move no window, and names we do not know, are inert", arguments: [
        #"{"_event":"mode-changed","mode":"resize"}"#,
        #"{"_event":"some-future-event","workspace":"1"}"#,
        // Stock AeroSpace emits no close event; the overview learns about closes from the
        // reload it does anyway. If upstream ever adds one, it lands here as a doorbell.
        #"{"_event":"window-closed","windowId":7}"#,
    ])
    func otherNamesAreInert(json: String) {
        #expect(AerospaceEvent.parse(json) == .other)
    }

    @Test("a line that is not an event at all is not an event", arguments: [
        "not json", "", #"{"windowId":42,"workspace":"1"}"#,
    ])
    func unparsableIsNil(json: String) {
        #expect(AerospaceEvent.parse(json) == nil)
    }
}
