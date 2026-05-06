import Testing
@testable import TauTUI

@Suite("Loader")
struct LoaderTests {
    @MainActor @Test
    func `tick advances frame and requests render`() {
        var renderCount = 0
        let loader = Loader(message: "Loading", autoStart: false) {
            renderCount += 1
        }
        loader.tick()
        #expect(renderCount == 1)
        let output = loader.render(width: 20)
        #expect(output[1].contains("Loading"))
    }
}
