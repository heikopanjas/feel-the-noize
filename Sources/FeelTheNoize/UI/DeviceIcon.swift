import AppKit

/// Device symbols in the status menu, drawn in a circle like the macOS Sound menu (Docs/DESIGN.md §7.11).
///
/// Core Audio offers no device artwork (`kAudioDevicePropertyIcon` is absent on every device tested), so the symbol is
/// chosen from the transport, the Apple product ID of Bluetooth devices and, for built-in devices, the system-given name.
nonisolated enum DeviceIcon {
    enum Direction {
        case output
        case input
    }

    /// Measured on the macOS Sound menu: a 26 pt circle with a 13 pt glyph.
    static let diameter: CGFloat = 26
    private static let glyphPointSize: CGFloat = 13
    private static let appleVendorID = 0x4C
    private static let headphoneJackSource: UInt32 = 0x6864_706E  // 'hdpn'
    private static let speakerSymbol = "speaker.wave.2.fill"
    private static let headphonesSymbol = "headphones"

    /// Apple Bluetooth product IDs from public device lists; only AirPods Max (USB-C) is verified on hardware so far.
    private static let appleProductSymbols: [Int: String] = [
        0x2002: "airpods", 0x200F: "airpods",
        0x2013: "airpods.gen3",
        0x2019: "airpods.gen4", 0x201B: "airpods.gen4",
        0x200E: "airpods.pro", 0x2014: "airpods.pro", 0x2024: "airpods.pro",
        0x200A: "airpods.max", 0x201F: "airpods.max"
    ]

    static func symbolName(for device: AudioDeviceInfo, direction: Direction) -> String {
        let generic = direction == .output ? Self.speakerSymbol : "mic.fill"
        switch device.transport {
            case .builtIn:
                return Self.builtInSymbolName(for: device, direction: direction, generic: generic)
            case .bluetooth:
                return Self.appleProductID(fromModelUID: device.modelUID).flatMap { Self.appleProductSymbols[$0] } ?? Self.headphonesSymbol
            case .hdmi:
                return "display"
            case .displayPort:
                return "display"
            case .airPlay:
                return "airplayaudio"
            // The Sound menu shows USB interfaces and the Continuity Camera microphone with the generic symbols too.
            case .usb:
                return generic
            case .thunderbolt:
                return generic
            case .virtual:
                return generic
            case .aggregate:
                return generic
            case .other:
                return generic
        }
    }

    /// The volume slider shows the headphone symbol for headphones, as the Sound menu does, and a speaker for anything else.
    static func sliderSymbolName(for output: AudioDeviceInfo?) -> String {
        guard let output = output else {
            return Self.speakerSymbol
        }
        let symbol = Self.symbolName(for: output, direction: .output)
        if symbol == Self.headphonesSymbol {
            return symbol
        }
        if symbol.hasPrefix("airpods") == true {
            return symbol
        }
        return Self.speakerSymbol
    }

    /// Bluetooth model UIDs read "<product> <vendor>" in hex; `nil` for any other shape or vendor.
    static func appleProductID(fromModelUID modelUID: String?) -> Int? {
        guard let parts = modelUID?.split(separator: " ") else {
            return nil
        }
        guard parts.count == 2 else {
            return nil
        }
        guard let product = Int(parts[0], radix: 16) else {
            return nil
        }
        guard let vendor = Int(parts[1], radix: 16) else {
            return nil
        }
        guard vendor == Self.appleVendorID else {
            return nil
        }
        return product
    }

    /// The default device gets the accent circle with a white glyph, the others a gray circle with a label-colored glyph.
    /// Colors resolve when the menu draws, so the image follows light and dark mode and the accent color. Hierarchical
    /// rendering fills secondary layers, such as the MacBook screen, at reduced opacity, as the Sound menu does.
    static func image(symbolName: String, isDefault: Bool, accessibilityDescription: String?) -> NSImage {
        let image = NSImage(size: NSSize(width: Self.diameter, height: Self.diameter), flipped: false) { rect in
            Self.draw(symbolName: symbolName, isDefault: isDefault, in: rect)
            return true
        }
        image.accessibilityDescription = accessibilityDescription
        return image
    }

    /// The headphone jack by its data source; otherwise built-in names come from the system and keep the product name in
    /// every language.
    private static func builtInSymbolName(for device: AudioDeviceInfo, direction: Direction, generic: String) -> String {
        if direction == .output {
            if device.outputDataSource == Self.headphoneJackSource {
                return Self.headphonesSymbol
            }
        }
        if device.name.contains("MacBook") == true {
            return "macbook"
        }
        if device.name.contains("iMac") == true {
            return "desktopcomputer"
        }
        return generic
    }

    private static func draw(symbolName: String, isDefault: Bool, in rect: NSRect) -> Void {
        let circleColor: NSColor = isDefault == true ? .controlAccentColor : .quaternaryLabelColor
        circleColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let glyphColor: NSColor = isDefault == true ? .white : .labelColor
        let configuration = NSImage.SymbolConfiguration(pointSize: Self.glyphPointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: glyphColor))
        guard let glyph = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else {
            return
        }
        let size = glyph.size
        glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
    }
}
