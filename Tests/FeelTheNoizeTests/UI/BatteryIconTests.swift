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

    @Test("Each cell's text is followed by its own symbol", arguments: [1, 3])
    func textWithSymbolPerCell(count: Int) -> Void {
        let cells = [(text: "L 80 %", level: 80), (text: "R 75 %", level: 75), (text: "case 40 %", level: 40)].prefix(count)
        let text = BatteryIcon.attributedText(Array(cells))
        var symbolCount = 0
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            if value != nil {
                symbolCount += 1
            }
        }
        #expect(symbolCount == count)
        for cell in cells {
            #expect(text.string.contains(cell.text + "\u{2002}") == true)
        }
    }

    @Test func noTextWithoutCells() -> Void {
        #expect(BatteryIcon.attributedText([]).length == 0)
    }
}
