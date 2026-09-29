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

    @Test func anythingElseIsTheMap() {
        #expect(summon("aerocontrol://anything-else") == .map)
        #expect(summon("aerocontrol://open?url=https://example.com") == .map)
    }
}
