import AppKit
import Testing

@testable import FeelTheNoize

struct BatteryIconTests {
    @Test(
        "Fill follows the level, clamped, with a sliver for any charge",
        arguments: [(0, 0.0), (1, 0.08), (50, 0.5), (100, 1.0), (150, 1.0), (-5, 0.0)] as [(Int, Double)])
    func fill(level: Int, expected: Double) -> Void {
        expectClose(Double(BatteryIcon.fillFraction(level: level)), expected, tolerance: 0.0001)
    }

    @Test("Image has the measured size and draws ink", arguments: [5, 85])
    func image(level: Int) throws -> Void {
        let image = BatteryIcon.image(level: level, accessibilityDescription: "battery")
        #expect(image.size == BatteryIcon.size)
        #expect(image.accessibilityDescription == "battery")
        let rep = try #require(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
        let inked = (0 ..< rep.pixelsWide).flatMap { x in (0 ..< rep.pixelsHigh).map { (x, $0) } }
            .filter { (rep.colorAt(x: $0.0, y: $0.1)?.alphaComponent ?? 0) > 0.3 }
        #expect(inked.count > 20)
    }

    @Test func textWithSymbolForSingleCellOnly() -> Void {
        let single = BatteryIcon.attributedText("96 %", level: 96)
        #expect(single.string.hasPrefix("96 %") == true)
        #expect(single.containsAttachments(in: NSRange(location: 0, length: single.length)) == true)
        let parts = BatteryIcon.attributedText("L 80 %, R 75 %", level: nil)
        #expect(parts.string == "L 80 %, R 75 %")
        #expect(parts.containsAttachments(in: NSRange(location: 0, length: parts.length)) == false)
    }
}
