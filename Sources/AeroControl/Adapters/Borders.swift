import AppKit

enum Borders {
    static let paths = ["/opt/homebrew/bin/borders", "/usr/local/bin/borders"]

    static var running: Bool {
        let pgrep = Process()
        pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        pgrep.arguments = ["-x", "borders"]
        pgrep.standardOutput = FileHandle.nullDevice
        try? pgrep.run()
        pgrep.waitUntilExit()
        return pgrep.terminationStatus == 0
    }

    static func matchAccent() {
        guard running, let path = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let accent = NSApp.effectiveAppearance.performAsCurrentDrawingAppearance { hex(.controlAccentColor) }
        let borders = Process()
        borders.executableURL = URL(fileURLWithPath: path)
        borders.arguments = ["active_color=0xff\(accent)", "inactive_color=0x40\(accent)"]
        try? borders.run()
    }

    static func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        return String(format: "%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
