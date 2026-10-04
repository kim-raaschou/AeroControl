import Testing
import Common
import Foundation
@testable import AeroControlKit

@Suite("Summon")
struct SummonTests {
    private func summon(_ string: String) -> Summon { Summon(URL(string: string)!) }

    @Test func aLinkNamesWhatTheOverviewOpensShowing() {
        #expect(summon("aerocontrol://workspaces") == .map)
        #expect(summon("aerocontrol://") == .map)
        #expect(summon("aerocontrol://com.apple.finder") == .app(bundleId: "com.apple.finder"))
        #expect(summon("aerocontrol://Company.TheBrowser.Browser") == .app(bundleId: "Company.TheBrowser.Browser"))   // the case is kept
    }

    @Test("while the overview is up the strip's own key steps it; any other app key is the app's whole flow again, the strip taking over; the map's key closes")
    func againWhileUp() {
        #expect(Summon.map.again(stripApp: nil) == .close && Summon.map.again(stripApp: "com.arc") == .close)
        #expect(Summon.app(bundleId: "com.arc").again(stripApp: "com.arc") == .step)
        #expect(Summon.app(bundleId: "com.claude").again(stripApp: nil) == .summon(app: "com.claude"))
        #expect(Summon.app(bundleId: "com.claude").again(stripApp: "com.arc") == .summon(app: "com.claude"))
    }

    @Test func anythingElseIsTheMap() {
        #expect(summon("aerocontrol://anything-else") == .map)
        #expect(summon("aerocontrol://open?url=https://example.com") == .map)
    }
}
