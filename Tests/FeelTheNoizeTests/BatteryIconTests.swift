import AppKit
import Testing

@testable import FeelTheNoize

struct BatteryIconTests {
    @Test(
        "Fill follows the level, clamped, with a sliver for any charge",
        arguments: [(0, 0.0), (1, 0.08), (50, 0.5), (100, 1.0), (150, 1.0), (-5, 0.0)] as [(Int, Double)])
    func fill(level: Int, expected: Double) {
        #expect(abs(Double(BatteryIcon.fillFraction(level: level)) - expected) < 0.0001)
    }

    @Test("Image has the measured size and draws ink", arguments: [5, 85])
    func image(level: Int) throws {
        let image = BatteryIcon.image(level: level, accessibilityDescription: "battery")
        #expect(image.size == BatteryIcon.size)
        #expect(image.accessibilityDescription == "battery")
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let inked = (0 ..< rep.pixelsWide).flatMap { x in (0 ..< rep.pixelsHigh).map { (x, $0) } }
            .filter { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 0) > 0.3 }
        #expect(inked.count > 20)
    }
}
