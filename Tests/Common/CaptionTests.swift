import Testing
@testable import Common

@Suite("WindowInfo.caption")
struct CaptionTests {
    @Test("the title without the app's name at its end; the app's name when there is no title", arguments: [
        ("README.md — Visual Studio Code", "Visual Studio Code", "README.md"),
        ("Inbox – Mail", "Mail", "Inbox"),
        ("notes - Notes", "Notes", "notes"),
        ("Crew standup | Microsoft Teams", "Microsoft Teams", "Crew standup"),
        ("readme.md — visual studio code", "Visual Studio Code", "readme.md"),   // case does not matter
        ("Visual Studio Code", "Visual Studio Code", "Visual Studio Code"),     // the title is only the name: kept
        ("Codex — Arc", "Visual Studio Code", "Codex — Arc"),                    // another app's name: left alone
        ("", "Arc", "Arc"),
        ("   ", "Arc", "Arc"),
    ] as [(String, String, String)])
    func caption(title: String, app: String, expected: String) {
        #expect(WindowInfo(windowId: 1, appName: app, bundleId: "x", title: title).caption == expected)
    }
}
