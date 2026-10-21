import AppKit
import Testing

@testable import FeelTheNoize

struct AccessoryBatteryTests {
    @Test(
        "Bluetooth address from Core Audio UIDs and power source identifiers",
        arguments: [
            ("70-F9-4A-A8-CE-BF:output", String?.some("70F94AA8CEBF")),
            ("70:f9:4a:a8:ce:bf", "70F94AA8CEBF"),
            ("AppleUSBAudioEngine:MOTU:M2:M2MA1307XA:1,2", nil),
            ("C132E7E4-A0B8-2D02-BE44-B373CD9AA007", nil),
            ("BuiltInSpeakerDevice", nil)
        ] as [(String, String?)])
    func address(text: String, expected: String?) -> Void {
        #expect(AccessoryBattery.address(in: text) == expected)
    }

    @Test func singleCellFromTheAirPodsMaxCapture() throws -> Void {
        let batteries = AccessoryBattery.batteries(from: [
            [
                "Accessory Identifier": "70:F9:4A:A8:CE:BF", "Group Identifier": "70:F9:4A:A8:CE:BF", "Part Identifier": "Single",
                "Current Capacity": 96, "Name": "AirPods Max"
            ]
        ])
        let battery = try #require(batteries["70F94AA8CEBF"])
        #expect(battery.text == "96 %")
        #expect(battery.singleLevel == 96)
    }

    @Test func airPodsPartsAreGroupedAndOrdered() throws -> Void {
        let group = "AA:BB:CC:DD:EE:FF"
        let batteries = AccessoryBattery.batteries(from: [
            ["Group Identifier": group, "Accessory Identifier": "AA:BB:CC:DD:EE:01", "Part Identifier": "Case", "Current Capacity": 40],
            ["Group Identifier": group, "Accessory Identifier": "AA:BB:CC:DD:EE:02", "Part Identifier": "Right", "Current Capacity": 75],
            ["Group Identifier": group, "Accessory Identifier": "AA:BB:CC:DD:EE:03", "Part Identifier": "Left", "Current Capacity": 80]
        ])
        let battery = try #require(batteries["AABBCCDDEEFF"])
        #expect(battery.text == "L 80 %, R 75 %, case 40 %")
        #expect(battery.singleLevel == nil)
    }

    @Test func sourcesWithoutAddressOrLevelAreSkipped() -> Void {
        let batteries = AccessoryBattery.batteries(from: [
            ["Accessory Identifier": "C132E7E4-A0B8-2D02-BE44-B373CD9AA007", "Current Capacity": 98, "Name": "Surface Dial"],
            ["Accessory Identifier": "11:22:33:44:55:66", "Part Identifier": "Case"],
            ["Accessory Identifier": "11:22:33:44:55:77", "Part Identifier": "Unknown", "Current Capacity": 50]
        ])
        #expect(batteries.isEmpty == true)
    }

    @Test func casePartLeftOutWhileItReportsNothing() throws -> Void {
        let batteries = AccessoryBattery.batteries(from: [
            ["Group Identifier": "AA:BB:CC:DD:EE:FF", "Part Identifier": "Left", "Current Capacity": 80],
            ["Group Identifier": "AA:BB:CC:DD:EE:FF", "Part Identifier": "Case"]
        ])
        #expect(try #require(batteries["AABBCCDDEEFF"]).text == "L 80 %")
    }

    @Test func levelsAreClampedToPercent() throws -> Void {
        let batteries = AccessoryBattery.batteries(from: [
            ["Accessory Identifier": "AA:BB:CC:DD:EE:FF", "Part Identifier": "Single", "Current Capacity": 140]
        ])
        #expect(try #require(batteries["AABBCCDDEEFF"]).singleLevel == 100)
    }

    @Test func dialFoundByVendorAndProduct() -> Void {
        let descriptions: [[String: Any]] = [
            ["Accessory Identifier": "70:F9:4A:A8:CE:BF", "Vendor ID": 76, "Product ID": 8223, "Current Capacity": 96],
            [
                "Accessory Identifier": "C132E7E4-A0B8-2D02-BE44-B373CD9AA007", "Name": "Surface Dial", "Vendor ID": 1118,
                "Product ID": 2331, "Current Capacity": 98
            ]
        ]
        #expect(AccessoryBattery.dialLevel(from: descriptions) == 98)
        #expect(AccessoryBattery.dialLevel(from: Array(descriptions.prefix(1))) == nil)
    }
}
