import Foundation
import Testing
@testable import Common

// MARK: - b-argv-pins — the exact wire form of the read/subscribe commands.

@Suite("AerospaceCommand argv (list & subscribe)")
struct AerospaceCommandArgvTests {
    @Test("list-windows argv is pinned")
    func listWindows() {
        #expect(AerospaceCommand.listWindows() == [
            "list-windows", "--all", "--json", "--format",
            "%{window-id} %{app-name} %{app-bundle-id} %{workspace} %{window-parent-container-layout} %{monitor-id}",
        ])
    }

    @Test("list-workspaces argv is pinned")
    func listWorkspaces() {
        #expect(AerospaceCommand.listWorkspaces() == [
            "list-workspaces", "--monitor", "all", "--json", "--format",
            "%{workspace} %{monitor-id}",
        ])
    }

    @Test("list-monitors argv is pinned")
    func listMonitors() {
        #expect(AerospaceCommand.listMonitors() == [
            "list-monitors", "--json", "--format",
            "%{monitor-id} %{monitor-name} %{monitor-appkit-nsscreen-screens-id}",
        ])
    }

    @Test("subscribe argv is pinned")
    func subscribe() {
        #expect(AerospaceCommand.subscribe() == ["subscribe", "--all"])
    }
}

// MARK: - b-drift-guard — a command's requested tokens must match its decoder's keys.

/// Distinct, non-fallback sentinel for a field, so that if a decoder's `CodingKeys`
/// literal drifts from the field's raw value the property falls back and the sentinel
/// assertion fails (or, for a required field, decode throws).
private func sentinel(for field: AerospaceField) -> Any {
    switch field {
    case .windowId: return 111
    case .appName: return "app"
    case .appBundleId: return "bundle"
    case .workspace: return "ws"
    case .parentLayout: return "pl"
    case .monitorId: return 222
    case .monitorName: return "mon"
    case .nsscreenId: return 333
    }
}

/// One JSON object whose keys are exactly the field tokens `fields` requests, each
/// carrying its sentinel value.
private func sentinelJSON(for fields: [AerospaceField]) -> String {
    let object = Dictionary(uniqueKeysWithValues: fields.map { ($0.rawValue, sentinel(for: $0)) })
    let data = try! JSONSerialization.data(withJSONObject: [object])
    return String(decoding: data, as: UTF8.self)
}

@Suite("field-token / decoder-key drift guard")
struct AerospaceFieldDriftGuardTests {
    @Test("every list-windows field lands in a DecodedWindow property")
    func windows() throws {
        let json = sentinelJSON(for: AerospaceCommand.listWindowsFields)
        let w = try #require(try JSONDecoder().decode([DecodedWindow].self, from: Data(json.utf8)).first)
        #expect(w.windowId == 111)
        #expect(w.appName == "app")
        #expect(w.appBundleId == "bundle")
        #expect(w.workspace == "ws")
        #expect(w.parentLayout == "pl")
        #expect(w.monitorId == 222)
    }

    @Test("every list-workspaces field lands in a WorkspaceMonitor property")
    func workspaces() throws {
        let m = try #require(try parseWorkspaces(json: sentinelJSON(for: AerospaceCommand.listWorkspacesFields)).first)
        #expect(m.workspace == "ws")
        #expect(m.monitorId == 222)
    }

    @Test("every list-monitors field lands in a DecodedMonitor property")
    func monitors() throws {
        let m = try #require(try parseMonitorList(json: sentinelJSON(for: AerospaceCommand.listMonitorsFields)).first)
        #expect(m.monitorId == 222)
        #expect(m.monitorName == "mon")
        #expect(m.nsscreenId == 333)
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

    @Test("acted-on names map to a real event; ignored names fall through to .other")
    func nameHandling() throws {
        // Names AeroSpace emits that AeroControl deliberately ignores (they can't change
        // the window/workspace layout), so the parser routes them to `.other`.
        let ignoredNames: Set<AerospaceEventName> = [.modeChanged]
        for name in AerospaceEventName.allCases {
            // window-detected requires a window-id to be actionable; supply one so this
            // guards the name mapping rather than the id-missing→.other guard.
            let payload = name == .windowDetected ? #","windowId":1"# : ""
            let json = #"{"_event":"\#(name.rawValue)"\#(payload)}"#
            let event = try #require(AerospaceEvent.parse(json), "\(name.rawValue) did not parse")
            if ignoredNames.contains(name) {
                #expect(event == .other, "\(name.rawValue) should fall through to .other")
            } else {
                #expect(event != .other, "\(name.rawValue) fell through to .other")
            }
        }
    }

    @Test("an unknown event name still maps to .other")
    func unknownIsOther() {
        #expect(AerospaceEvent.parse(#"{"_event":"totally-made-up"}"#) == .other)
    }
}
