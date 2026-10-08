import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import AeroControlKit
@testable import Common

/// Against the AeroSpace that is running, with Finder windows made for the test and closed
/// after it: what AeroSpace does when a window leaves a workspace the overview is not showing.
/// It uses the screen — windows open, the focus moves and comes back — so it runs only on
/// request, `make live-test`, never in `make test` or CI.
@Suite("AeroSpace, live", .enabled(if: ProcessInfo.processInfo.environment["AEROCONTROL_LIVE"] == "1"), .serialized)
struct AerospaceLiveTests {
    @Test("a quiet move out of a hidden workspace sends no event and moves no window there until it is shown, but AeroSpace's rects are the new layout at once: where the windows go when it is")
    func quietMoveOutOfHiddenWorkspace() throws {
        let home = try aerospace("list-windows", "--focused", "--format", "%{window-id}")
        let finder = { try aerospace("list-windows", "--monitor", "all", "--app-bundle-id", "com.apple.finder", "--format", "%{window-id}").split(separator: "\n").compactMap { Int($0) } }
        let before = try finder()
        for _ in 0..<3 { _ = try run("/usr/bin/osascript", ["-e", #"tell application "Finder" to make new Finder window"#]) }
        Thread.sleep(forTimeInterval: 1)
        let made = try finder().filter { !before.contains($0) }
        defer {
            for id in made { _ = try? aerospace("close", "--window-id", "\(id)") }
            _ = try? aerospace("focus", "--window-id", home)
        }
        try #require(made.count == 3)
        for id in made {
            _ = try aerospace("move-node-to-workspace", "--window-id", "\(id)", "ac-live-a")
            _ = try aerospace("layout", "--window-id", "\(id)", "tiling")                  // a config may float Finder's
        }
        _ = try aerospace("layout", "--window-id", "\(made[0])", "h_tiles")
        _ = try aerospace("workspace", "ac-live-a")                                     // shown once, laid out
        let (left, moved) = (Array(made.dropLast()), made.last!)
        try #require(try settle(left, "ac-live-a") != nil, "not laid out even while shown")
        _ = try aerospace("focus", "--window-id", home)                                 // ac-live-a hidden again
        let (laidOut, laidOutRects) = (sizes(left), try layoutRects("ac-live-a"))

        let events = try Subscription()
        _ = try aerospace("move-node-to-workspace", "--window-id", "\(moved)", "ac-live-b")
        Thread.sleep(forTimeInterval: 1)
        let rects = try layoutRects("ac-live-a")
        print("live: hidden, 1 s after the move: sizes \(sizes(left)), AeroSpace's rects \(rects), events \(events.lines)")
        #expect(sizes(left) == laidOut)                                                 // the windows did not widen into the hole,
        #expect(left.allSatisfy { rects[$0]!.width > laidOutRects[$0]!.width + 100 })   // but their rects did: the owner's branch lays hidden workspaces out
        #expect(events.lines.isEmpty)                                                   // and nothing was said

        _ = try aerospace("workspace", "ac-live-a")
        let settled = try #require(try settle(left, "ac-live-a"), "not laid out once shown")
        print("live: shown again, laid out and the windows took their rects after \(Int(settled * 1000)) ms")
        #expect(left.allSatisfy { sizes(left)[$0]!.width > laidOut[$0]!.width + 100 })  // only now
        let shown = try layoutRects("ac-live-a")
        #expect(left.allSatisfy { shown[$0] == rects[$0] })                             // the hidden rects were the layout it got,
        #expect(left.allSatisfy { abs(sizes(left)[$0]!.width - rects[$0]!.width) <= 2 })  // and the windows its size
    }

    @Test("workspace 1 in tiles and in stacked, read as the app reads it the moment the command returns, and laid out as its card lays it out")
    func workspaceOneTilesAndStacked() async throws {
        let roots = try aerospace("list-workspaces", "--monitor", "all", "--format", "%{workspace} %{workspace-root-container-layout}")
        let original = try #require(roots.split(separator: "\n").first { $0.hasPrefix("1 ") }?.split(separator: " ").last.map(String.init))
        defer { _ = try? aerospace("layout", "--workspace", "1", "--root", original) }
        let runner = AerospaceSocketRunner()
        let screen = CGRect(origin: .zero, size: NSScreen.screens[0].frame.size)
        func one() async throws -> WorkspaceInfo {
            try #require(try await loadOverview(using: runner).workspaces.first { $0.name == "1" })
        }
        func card(_ ws: WorkspaceInfo) -> (frames: [Int: CGRect], ghosts: Set<Int>)? {
            AeroControlLayout.treeLayout(ws, sizes: [:], screen: screen, inner: CGSize(width: 1000, height: 600))
        }

        _ = try aerospace("layout", "--workspace", "1", "--root", "h_tiles")
        let tiled = try await one()
        let xs = tiled.windows.compactMap { $0.layoutRect?.minX }
        print("live: ws 1 tiled, \(tiled.windows.count) windows at x \(xs.map { Int($0) })")
        #expect(tiled.rootLayout == "h_tiles" && xs.count == tiled.windows.count && xs == xs.sorted() && Set(xs).count == xs.count)  // side by side, in order
        let laid = try #require(card(tiled), "a tiled workspace with rects is a map")
        let tops = Set(tiled.windows.compactMap { laid.frames[$0.windowId]?.minY.rounded() })
        #expect(tops.count == 1 && laid.frames.count == tiled.windows.count)   // one row: every window drawn, all at one top

        _ = try aerospace("layout", "--workspace", "1", "--root", "h_accordion")
        let stacked = try await one()
        print("live: ws 1 stacked, rects \(Set(stacked.windows.compactMap { $0.layoutRect.map { "\(Int($0.minX)),\(Int($0.width))" } }))")
        #expect(stacked.rootLayout == "h_accordion")
        #expect(card(stacked) == nil)                                                   // all in one place: the card packs them
    }

    /// Seconds until every window's real width is its rect's on `workspace`, polled; nil after 3 s.
    private func settle(_ ids: [Int], _ workspace: String) throws -> Double? {
        let start = Date()
        while Date().timeIntervalSince(start) < 3 {
            let rects = try layoutRects(workspace), real = sizes(ids)
            if ids.allSatisfy({ id in real[id].map { abs($0.width - (rects[id]?.width ?? -9)) <= 2 } ?? false }) { return Date().timeIntervalSince(start) }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    /// Where AeroSpace has each window of `workspace`: `%{window-layout-rect}`, the owner's branch.
    private func layoutRects(_ workspace: String) throws -> [Int: CGRect] {
        try aerospace("list-windows", "--workspace", workspace, "--format", "%{window-id} %{window-layout-rect}")
            .split(separator: "\n").reduce(into: [:]) { all, line in
                let parts = line.split(separator: " "), r = parts.last!.split(separator: ",").compactMap { Double($0) }
                if let id = Int(parts[0]), r.count == 4 { all[id] = CGRect(x: r[0], y: r[1], width: r[2], height: r[3]) }
            }
    }

    /// The window server's size of each window: what the app made it, not what AeroSpace asked.
    private func sizes(_ ids: [Int]) -> [Int: CGSize] {
        let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.reduce(into: [:]) { all, w in
            guard let id = w[kCGWindowNumber as String] as? Int, ids.contains(id),
                  let b = w[kCGWindowBounds as String] as? [String: Double] else { return }
            all[id] = CGSize(width: b["Width"] ?? 0, height: b["Height"] ?? 0)
        }
    }
}

private func aerospace(_ args: String...) throws -> String {
    try run("/opt/homebrew/bin/aerospace", args).trimmingCharacters(in: .whitespacesAndNewlines)
}

private func run(_ path: String, _ args: [String]) throws -> String {
    let process = Process(), out = Pipe()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    process.standardOutput = out
    try process.run()
    process.waitUntilExit()
    let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    guard process.terminationStatus == 0 else { throw Failed(command: ([path] + args).joined(separator: " ")) }
    return text
}

private struct Failed: Error { let command: String }

/// AeroSpace's event stream from now on, as the overview hears it.
private final class Subscription: @unchecked Sendable {
    private let process = Process(), out = Pipe(), lock = NSLock()
    private var received: [String] = []
    var lines: [String] { lock.withLock { received } }

    init() throws {
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/aerospace")
        process.arguments = ["subscribe", "--all", "--no-send-initial"]
        process.standardOutput = out
        out.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let text = String(decoding: handle.availableData, as: UTF8.self)
            self?.lock.withLock { self?.received += text.split(separator: "\n").map(String.init) }
        }
        try process.run()
        Thread.sleep(forTimeInterval: 0.3)
    }

    deinit { process.terminate() }
}

extension AerospaceLiveTests {
    /// The whole read path against the running AeroSpace: both lists and both `--focused`
    /// reads, decoded into the model the overview draws. This is the one place that proves
    /// AeroSpace answers `--focused` the way we parse it.
    @Test("the whole read, focus included, as the running AeroSpace answers it")
    func loadOverviewReadsFocus() async throws {
        let result = try await loadOverview(using: AerospaceSocketRunner())
        #expect(!result.workspaces.isEmpty)
        let focus = try #require(result.focus)
        #expect(result.workspaces.contains { $0.name == focus.workspace })
    }
}
