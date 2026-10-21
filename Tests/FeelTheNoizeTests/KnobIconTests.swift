import AppKit
import Testing

@testable import FeelTheNoize

struct KnobIconTests {
    @Test(
        "Pointer sweeps 270 degrees clockwise from lower left",
        arguments: [(Float(0), 225.0), (0.5, 90.0), (1, -45.0), (-1, 225.0), (2, -45.0)] as [(Float, Double)])
    func pointer(level: Float, degrees: Double) {
        expectClose(Double(KnobIcon.pointerDegrees(for: level)), degrees, tolerance: 0.001)
    }

    @Test("Images are template images of the requested size", arguments: KnobIcon.Style.allCases)
    func image(style: KnobIcon.Style) {
        let image = KnobIcon.image(style: style, level: 0.4, isMuted: false, size: 18, accessibilityDescription: "Volume 40 %")
        #expect(image.isTemplate)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.accessibilityDescription == "Volume 40 %")
    }

    @Test("Draws something for every style and state", arguments: KnobIcon.Style.allCases, [false, true])
    func drawsInk(style: KnobIcon.Style, isMuted: Bool) throws {
        let image = KnobIcon.image(style: style, level: 0.7, isMuted: isMuted, size: 36, accessibilityDescription: nil)
        let data = try #require(image.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: data))
        let inked = (0 ..< rep.pixelsWide).flatMap { x in (0 ..< rep.pixelsHigh).map { (x, $0) } }
            .filter { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 0) > 0.5 }
        #expect(inked.count > 30)
    }

    @Test func stylesHaveTitles() {
        #expect(KnobIcon.Style.allCases.map(\.title) == ["Arc", "Ring", "Dots"])
    }
}
