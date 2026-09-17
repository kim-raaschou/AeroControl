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
            "%{window-id} %{app-name} %{app-bundle-id} %{window-title} %{workspace} %{window-parent-container-layout} %{monitor-id}",
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
        #expect(AerospaceCommand.subscribe() == ["subscribe", "--all"])
    }
}

// MARK: - b-event-name-pin — the declared event names must mirror AeroSpace's ServerEventType.

@Suite("AerospaceEventName pin")
struct AerospaceEventNamePinTests {
    @Test("the declared event-name set is pinned")
    func rawValuesArePinned() {
        #expect(Set(AerospaceEventName.allCases.map(\.rawValue)) == [
            "focus-changed",
            "focused-workspace-changed",
            "focused-monitor-changed",
            "mode-changed",
            "window-detected",
            "binding-triggered",
        ])
    }
}

// MARK: - b-parse — each stream line maps to its typed AerospaceEvent (value extraction).

@Suite("AerospaceEvent.parse")
struct AerospaceEventParseTests {

    @Test func focus_changed_with_windowId() {
        let json = #"{"_event":"focus-changed","windowId":42,"workspace":"3"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .focusChanged(windowId: 42, workspace: "3"))
    }

    @Test func focus_changed_without_windowId() {
        let json = #"{"_event":"focus-changed","workspace":"1"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .focusChanged(windowId: nil, workspace: "1"))
    }

    @Test func workspace_changed() {
        let json = #"{"_event":"focused-workspace-changed","workspace":"2","prevWorkspace":"1"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .workspaceChanged(workspace: "2", prevWorkspace: "1"))
    }

    @Test func workspace_changed_missing_fields_defaults_to_empty() {
        let json = #"{"_event":"focused-workspace-changed"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .workspaceChanged(workspace: "", prevWorkspace: ""))
    }

    @Test func monitor_changed() {
        let json = #"{"_event":"focused-monitor-changed","workspace":"4","monitorId":2}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .monitorChanged(workspace: "4", monitorId: 2))
    }

    @Test func monitor_changed_without_monitor_id() {
        let json = #"{"_event":"focused-monitor-changed","workspace":"4"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .monitorChanged(workspace: "4", monitorId: nil))
    }

    @Test func window_detected_full() {
        let json = #"{"_event":"window-detected","windowId":99,"workspace":"2","appBundleId":"com.apple.Safari","appName":"Safari"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .windowDetected(windowId: 99, workspace: "2", appBundleId: "com.apple.Safari", appName: "Safari"))
    }

    @Test func window_detected_minimal() {
        let json = #"{"_event":"window-detected","windowId":1}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .windowDetected(windowId: 1, workspace: nil, appBundleId: nil, appName: nil))
    }

    @Test func window_detected_missing_windowId_maps_to_other() {
        let json = #"{"_event":"window-detected"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .other)
    }

    @Test func unknown_event_returns_other() {
        let json = #"{"_event":"some-future-event","workspace":"1"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .other)
    }

    @Test func window_closed_is_not_parsed_we_emulate_it_locally() {
        // Stock AeroSpace emits no close event, so AeroControl doesn't recognise a
        // "window-closed" name on the stream — it emulates close locally instead
        // (`.localWindowClosed` from the native taps). An unknown name maps to `.other`.
        let json = #"{"_event":"window-closed","windowId":7}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .other)
    }

    @Test func mode_changed_maps_to_other() {
        let json = #"{"_event":"mode-changed","mode":"resize"}"#
        let event = AerospaceEvent.parse(json)
        #expect(event == .other)
    }

    @Test func invalid_json_returns_nil() {
        #expect(AerospaceEvent.parse("not json") == nil)
    }

    @Test func empty_string_returns_nil() {
        #expect(AerospaceEvent.parse("") == nil)
    }

    @Test func missing_event_field_returns_nil() {
        let json = #"{"windowId":42,"workspace":"1"}"#
        #expect(AerospaceEvent.parse(json) == nil)
    }
}
