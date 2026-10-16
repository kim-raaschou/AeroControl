import Testing
@testable import AeroControl

struct KeyHintTests {
    @Test("the hint's six places are named for the menu as a hand would say them")
    func placesAreNamed() {
        #expect(KeyHintPlace.allCases.map(\.title) == ["Top left", "Top", "Top right", "Bottom left", "Bottom", "Bottom right"])
    }
}
