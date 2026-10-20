import CoreBluetooth

/// Reads the Surface Dial's battery level through the standard Bluetooth Battery Service (docs/DESIGN.md §7.10).
///
/// The HID descriptor has no battery usage, but macOS lets apps read the Battery Service over the link the system
/// already holds for the Dial. Delegate callbacks arrive on the main queue.
final class DialBattery: NSObject {
    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevelCharacteristic = CBUUID(string: "2A19")
    private static let dialName = "Surface Dial"

    /// Called with the new level in percent, or `nil` when it becomes unknown.
    var onChange: ((Int?) -> Void)?

    private(set) var level: Int? {
        didSet {
            if level != oldValue {
                onChange?(level)
            }
        }
    }

    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var isDialConnected = false

    /// The central is created on the first connection, so the Bluetooth permission prompt only appears once a Dial is there.
    func dialConnected() {
        isDialConnected = true
        if let central {
            connectIfPossible(central)
        }
        else {
            central = CBCentralManager(delegate: self, queue: .main)
        }
    }

    func dialDisconnected() {
        isDialConnected = false
        // Only drops Feel the Noize's use of the link; the system keeps its own HID connection.
        if let central, let peripheral {
            central.cancelPeripheralConnection(peripheral)
        }
        peripheral = nil
        level = nil
    }

    private func connectIfPossible(_ central: CBCentralManager) {
        guard isDialConnected, central.state == .poweredOn, peripheral == nil else { return }
        let connected = central.retrieveConnectedPeripherals(withServices: [Self.batteryService])
        guard let dial = connected.first(where: { $0.name == Self.dialName }) else {
            Log.dial.notice("Surface Dial not found among Bluetooth peripherals with a battery service")
            return
        }
        peripheral = dial
        dial.delegate = self
        central.connect(dial)
    }
}

// MARK: - CBCentralManagerDelegate

extension DialBattery: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .unauthorized {
            Log.dial.notice("Bluetooth access denied; the Dial battery level is unavailable")
        }
        connectIfPossible(central)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batteryService])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        Log.dial.error("Connecting to the Dial battery service failed: \(String(describing: error), privacy: .public)")
        self.peripheral = nil
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, timestamp: CFAbsoluteTime, isReconnecting: Bool,
        error: (any Error)?
    ) {
        self.peripheral = nil
        level = nil
    }
}

// MARK: - CBPeripheralDelegate

extension DialBattery: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.batteryService }) else { return }
        peripheral.discoverCharacteristics([Self.batteryLevelCharacteristic], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        guard let characteristic = service.characteristics?.first(where: { $0.uuid == Self.batteryLevelCharacteristic }) else { return }
        peripheral.readValue(for: characteristic)
        // Notifications keep the level current without polling.
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard characteristic.uuid == Self.batteryLevelCharacteristic, let value = characteristic.value?.first else { return }
        level = min(Int(value), 100)
        Log.dial.info("Surface Dial battery level \(Int(value)) %")
    }
}
