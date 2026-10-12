import CoreGraphics
import Testing
@testable import NotchPrompterKit

@Suite("Plug-in window size")
struct PluginWindowSizeTests {

    @Test("the plug-in's preferred size comes first")
    func preferred() {
        #expect(PluginWindowSize.initial(preferred: CGSize(width: 600, height: 400), view: CGSize(width: 792, height: 450))
            == CGSize(width: 600, height: 400))
    }

    @Test("without a preferred size, the view's own size", arguments: [CGSize.zero, CGSize(width: 1, height: 1)])
    func viewSize(preferred: CGSize) {
        #expect(PluginWindowSize.initial(preferred: preferred, view: CGSize(width: 792, height: 450))
            == CGSize(width: 792, height: 450))
    }

    @Test("a view that has not been laid out gets the fallback size")
    func fallback() {
        #expect(PluginWindowSize.initial(preferred: .zero, view: CGSize(width: 1, height: 1)) == PluginWindowSize.fallback)
    }

    @Test("the window follows a plug-in that resizes itself, but not a view collapsing to nothing")
    func followed() {
        #expect(PluginWindowSize.followed(CGSize(width: 900, height: 500)) == CGSize(width: 900, height: 500))
        #expect(PluginWindowSize.followed(.zero) == nil)
        #expect(PluginWindowSize.followed(CGSize(width: 1, height: 1)) == nil)
    }
}
