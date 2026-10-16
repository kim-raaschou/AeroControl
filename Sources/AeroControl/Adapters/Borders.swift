import AppKit

enum Borders {
    static var running: Bool {
        (try? Process.run(URL(fileURLWithPath: "/usr/bin/pgrep"), arguments: ["-x", "borders"])).map { $0.waitUntilExit(); return $0.terminationStatus == 0 } ?? false
    }

    static func matchAccent() {
        guard running, let path = ["/opt/homebrew/bin/borders", "/usr/local/bin/borders"].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let accent = NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { hex(.controlAccentColor) }
        _ = try? Process.run(URL(fileURLWithPath: path), arguments: ["active_color=0xff\(accent)", "inactive_color=0x40\(accent)"])
    }

    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
