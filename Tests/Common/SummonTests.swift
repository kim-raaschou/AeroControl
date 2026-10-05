import Testing
@testable import Common
import Foundation
@testable import AeroControlKit

@Suite("Summon")
struct SummonTests {
    private func summon(_ string: String) -> Summon { Summon(URL(string: string)!) }
    private func w(_ id: Int, _ name: String, _ bundle: String) -> WindowInfo { WindowInfo(windowId: id, appName: name, bundleId: bundle) }

    @Test("a link names what the overview opens showing: the map, or an app by AeroSpace's own two names for it")
    func aLinkNamesWhatTheOverviewOpensShowing() {
        #expect(summon("aerocontrol://workspaces") == .map)
        #expect(summon("aerocontrol://") == .map)
        #expect(summon("aerocontrol://app-id=com.apple.finder") == .app(.bundleId("com.apple.finder")))
        #expect(summon("aerocontrol://app-id=Company.TheBrowser.Browser") == .app(.bundleId("Company.TheBrowser.Browser")))   // the case is kept
        #expect(summon("aerocontrol://app-name=Finder") == .app(.name("Finder")))
        #expect(summon("aerocontrol://app-name=Microsoft%20Teams") == .app(.name("Microsoft Teams")))                       // spaces as %20
    }

    @Test("anything else is the map: a bare word, a bundle id without its key, an unknown key")
    func anythingElseIsTheMap() {
        #expect(summon("aerocontrol://anything-else") == .map)
        #expect(summon("aerocontrol://com.apple.finder") == .map)
        #expect(summon("aerocontrol://pid=42") == .map)
        #expect(summon("aerocontrol://open?url=https://example.com") == .map)
    }

    @Test("an app reference picks the app's windows by bundle id or by name, and says whether a strip is its")
    func appRef() {
        let windows = [w(1, "Arc", "com.arc"), w(2, "Mail", "com.mail"), w(3, "Arc", "com.arc")]
        #expect(windows.filter(AppRef.bundleId("com.arc").matches).map(\.windowId) == [1, 3])
        #expect(windows.filter(AppRef.name("Mail").matches).map(\.windowId) == [2])
        #expect(AppRef.name("Arc").identifies(bundleId: "com.arc", among: windows))
        #expect(!AppRef.name("Arc").identifies(bundleId: "com.mail", among: windows))
        #expect(AppRef.bundleId("com.mail").identifies(bundleId: "com.mail", among: windows))
    }

    @Test("the line that binds a key to an app is AeroSpace's own syntax, its link the app-id one a summon reads back")
    func binding() throws {
        let line = aerospaceBinding(for: WindowInfo(windowId: 1, appName: "Arc", bundleId: "company.thebrowser.Browser"))
        #expect(line == #"<key> = ['exec-and-forget open "aerocontrol://app-id=company.thebrowser.Browser"']  # Arc"#)
        let link = try #require(line.split(separator: "\"").first { $0.hasPrefix("aerocontrol://") })
        #expect(Summon(try #require(URL(string: String(link)))) == .app(.bundleId("company.thebrowser.Browser")))
    }

    @Test("one key per app: none, start; one, focus it; two and you are in one, the other; otherwise the strip, on the one after yours", arguments: [
        ([Int](), 0, AppSummon.launch(.bundleId("a"))),
        ([7], 0, .focus(windowId: 7)),
        ([1, 2], 1, .focus(windowId: 2)),
        ([1, 2], 2, .focus(windowId: 1)),                                              // and back
        ([1, 2], 9, .pick(Strip(bundleId: "a", marked: 1, centre: 1, turns: 0))),      // from another app
        ([1, 2, 3], 2, .pick(Strip(bundleId: "a", marked: 3, centre: 3, turns: 0))),
    ] as [([Int], Int, AppSummon)])
    func decide(app: [Int], focused: Int, expected: AppSummon) {
        let windows = app.map { WindowInfo(windowId: $0, appName: "A", bundleId: "a") } + [WindowInfo(windowId: 9, appName: "B", bundleId: "b")]
        let model = OverviewModel(workspaces: [WorkspaceInfo(name: "1", windows: windows)], focusedWindowId: focused, focusedWorkspace: "1")
        #expect(AppSummon.decide(app: .bundleId("a"), model: model, recent: []) == expected)
    }

    @Test("an app nothing answers to is told by the name the link gave, and why nothing came")
    func notFound() {
        let id = AppRef.bundleId("com.typo").notFound, name = AppRef.name("Two Words").notFound
        #expect(id.name == "com.typo" && id.reason == "no app has this id")
        #expect(name.name == "Two Words" && name.reason == "no app has this name")
    }

    @Test("while the overview is up the strip's own key steps it, by either name; any other app key is the app's whole flow again; the map's key closes")
    func againWhileUp() {
        let windows = [w(1, "Arc", "com.arc"), w(2, "Claude", "com.claude")]
        #expect(Summon.map.again(stripApp: nil, among: windows) == .close && Summon.map.again(stripApp: "com.arc", among: windows) == .close)
        #expect(Summon.app(.bundleId("com.arc")).again(stripApp: "com.arc", among: windows) == .step)
        #expect(Summon.app(.name("Arc")).again(stripApp: "com.arc", among: windows) == .step)
        #expect(Summon.app(.bundleId("com.claude")).again(stripApp: nil, among: windows) == .summon(.bundleId("com.claude")))
        #expect(Summon.app(.name("Claude")).again(stripApp: "com.arc", among: windows) == .summon(.name("Claude")))
    }
}
