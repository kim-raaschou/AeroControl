import Testing
import Common
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
