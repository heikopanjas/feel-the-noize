import Foundation
import IOKit.ps

/// Battery levels of Bluetooth accessories such as AirPods and of the Surface Dial, from the accessory power sources
/// (docs/DESIGN.md §7.10, §7.12).
///
/// `IOPSCopyPowerSourcesByType` is exported by IOKit but has no header, so it is looked up with `dlsym`; type 4 returns the
/// accessory sources, decoded with the public `IOPSCopyPowerSourcesList` and `IOPSGetPowerSourceDescription`. If the
/// symbol is missing, `read()` returns no batteries and the menu shows none.
struct AccessoryBattery: Equatable {
    enum Part: Int, Comparable {
        case left
        case right
        case chargingCase
        case single

        init?(identifier: String?) {
            switch identifier {
                case "Left": self = .left
                case "Right": self = .right
                case "Case": self = .chargingCase
                case "Single", nil: self = .single
                default: return nil
            }
        }

        static func < (lhs: Part, rhs: Part) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct Cell: Equatable {
        let part: Part
        let level: Int
    }

    /// One read of the power sources.
    struct Readings: Equatable {
        /// Audio accessories by Bluetooth address.
        var devices: [String: AccessoryBattery] = [:]
        /// The Surface Dial reports as a Bluetooth LE source identified by a UUID, so it is found by vendor and product ID.
        var dialLevel: Int?
    }

    /// Bluetooth address as twelve uppercase hex digits, the key shared with Core Audio device UIDs.
    let address: String
    /// Sorted left, right, case, single; parts that report no level are left out.
    let cells: [Cell]

    private typealias CopyPowerSourcesByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?
    private static let accessoryType: Int32 = 4
    /// Microsoft and the Surface Dial, as the power source reports them.
    private static let dialVendorID = 1118
    private static let dialProductID = 2331

    /// The level of a single-cell device, which the menu shows with a battery symbol.
    var singleLevel: Int? {
        cells.count == 1 && cells[0].part == .single ? cells[0].level : nil
    }

    /// "80 %" for a single cell, "L 80 %, R 75 %, case 40 %" for AirPods.
    var text: String {
        cells.map { cell in
            switch cell.part {
                case .left: "L \(cell.level) %"
                case .right: "R \(cell.level) %"
                case .chargingCase: "case \(cell.level) %"
                case .single: "\(cell.level) %"
            }
        }
        .joined(separator: ", ")
    }

    // MARK: - Reading

    /// Reads all accessory batteries. One in-process call; no permission prompt.
    static func read() -> Readings {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "IOPSCopyPowerSourcesByType") else {
            Log.audio.error("IOPSCopyPowerSourcesByType is missing; battery levels are not shown")
            return Readings()
        }
        let copy = unsafeBitCast(symbol, to: CopyPowerSourcesByType.self)
        guard let blob = copy(accessoryType)?.takeRetainedValue() else { return Readings() }
        let sources = IOPSCopyPowerSourcesList(blob).takeRetainedValue() as [CFTypeRef]
        let descriptions = sources.compactMap { IOPSGetPowerSourceDescription(blob, $0)?.takeUnretainedValue() as? [String: Any] }
        return Readings(devices: batteries(from: descriptions), dialLevel: dialLevel(from: descriptions))
    }

    static func dialLevel(from descriptions: [[String: Any]]) -> Int? {
        let dial = descriptions.first {
            $0["Vendor ID"] as? Int == dialVendorID && $0["Product ID"] as? Int == dialProductID
        }
        return (dial?["Current Capacity"] as? Int).map { min(max($0, 0), 100) }
    }

    /// Groups the parts of one device by `Group Identifier`, falling back to `Accessory Identifier`. Sources without a
    /// Bluetooth address, such as Bluetooth LE devices identified by a UUID, are skipped.
    static func batteries(from descriptions: [[String: Any]]) -> [String: AccessoryBattery] {
        var cells: [String: [Cell]] = [:]
        for description in descriptions {
            let identifier = (description["Group Identifier"] ?? description["Accessory Identifier"]) as? String
            guard let address = identifier.flatMap(Self.address(in:)),
                let part = Part(identifier: description["Part Identifier"] as? String),
                let level = description["Current Capacity"] as? Int
            else { continue }
            cells[address, default: []].append(Cell(part: part, level: min(max(level, 0), 100)))
        }
        return cells.mapValues { $0.sorted { $0.part < $1.part } }
            .reduce(into: [:]) { result, entry in result[entry.key] = AccessoryBattery(address: entry.key, cells: entry.value) }
    }

    /// Finds a Bluetooth address such as `70-F9-4A-A8-CE-BF` in a Core Audio UID or `70:F9:4A:A8:CE:BF` in a power source.
    static func address(in text: String) -> String? {
        guard let match = text.firstMatch(of: /([0-9A-Fa-f]{2}[-:]){5}[0-9A-Fa-f]{2}/) else { return nil }
        return String(match.output.0).filter(\.isHexDigit).uppercased()
    }
}
