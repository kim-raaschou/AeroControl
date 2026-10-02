import Testing
import Foundation
@testable import AeroControlKit

@Suite("Summon")
struct SummonTests {
    private func summon(_ string: String) -> Summon { Summon(URL(string: string)!) }

    @Test func aLinkNamesWhatTheOverviewOpensShowing() {
        #expect(summon("aerocontrol://workspaces") == .map)
        #expect(summon("aerocontrol://windows") == .focusedApp)
        #expect(summon("aerocontrol://windows?app=com.apple.finder") == .app(bundleId: "com.apple.finder"))
    }

    @Test("while the overview is up the strip's own key steps it and another app's key focuses that app; anything else closes it")
    func againWhileUp() {
        #expect(Summon.map.again(stripApp: nil) == .close)
        #expect(Summon.focusedApp.again(stripApp: "com.arc") == .step)
        #expect(Summon.app(bundleId: "com.arc").again(stripApp: "com.arc") == .step)
        #expect(Summon.app(bundleId: "com.claude").again(stripApp: nil) == .focus(app: "com.claude"))
        #expect(Summon.app(bundleId: "com.claude").again(stripApp: "com.arc") == .focus(app: "com.claude"))
        #expect(Summon.map.again(stripApp: "com.arc") == .close && Summon.focusedApp.again(stripApp: nil) == .close)
    }

    @Test func anythingElseIsTheMap() {
        #expect(summon("aerocontrol://anything-else") == .map)
        #expect(summon("aerocontrol://open?url=https://example.com") == .map)
    }
}
