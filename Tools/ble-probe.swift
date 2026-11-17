// Passive feasibility probe. No connections, pairing requests, or screen locks.
// Build with Tools/BluetoothProbe.plist embedded as __TEXT,__info_plist.
// Run: .build/ble-probe --seconds 45 --label phone-on > .build/ble-phone-on.jsonl
import CoreBluetooth
import Foundation

func emit(_ event: String, _ fields: [String: Any] = [:]) {
    var record = fields
    record["event"] = event
    record["time"] = ISO8601DateFormatter().string(from: Date())
    let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}
func fail(_ message: String) -> Never {
    emit("error", ["message": message])
    exit(1)
}
func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

var seconds = 45
var label = "unlabelled"
let args = Array(CommandLine.arguments.dropFirst())
if args == ["--help"] {
    print("Usage: ble-probe [--seconds 1...600] [--label phone-on|phone-off|phone-returned]")
    exit(0)
}
var index = 0
while index < args.count {
    let option = args[index]
    guard ["--seconds", "--label"].contains(option), index + 1 < args.count else {
        fail("Expected --seconds <1...600> or --label <phase>.")
    }
    index += 1
    if option == "--seconds" {
        guard let value = Int(args[index]), (1...600).contains(value) else { fail("Seconds must be 1...600.") }
        seconds = value
    } else { label = args[index] }
    index += 1
}

final class Recorder: NSObject, CBCentralManagerDelegate {
    var central: CBCentralManager!
    var scanningSince: TimeInterval?
    var devices: [UUID: CBPeripheral] = [:]
    var counts: [UUID: Int] = [:]
    var packets = 0

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emit("bluetooth_state", ["state": central.state.rawValue, "authorization": CBCentralManager.authorization.rawValue])
        switch central.state {
        case .poweredOn:
            scanningSince = ProcessInfo.processInfo.systemUptime
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            emit("scan_start", ["label": label, "seconds": seconds])
        case .unauthorized: fail("Bluetooth permission is required for this passive scan.")
        case .unsupported: fail("This Mac does not support Bluetooth LE scanning.")
        case .poweredOff: fail("Turn on Bluetooth on the Mac before this scan.")
        default: break
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        let id = peripheral.identifier
        devices[id] = peripheral
        counts[id, default: 0] += 1
        packets += 1
        let manufacturer = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data ?? Data()
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []).map(\.uuidString)
        let serviceData = (advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] ?? [:])
        let data = Dictionary(uniqueKeysWithValues: serviceData.map { ($0.key.uuidString, hex($0.value)) })
        emit("advertisement", ["label": label, "id": id.uuidString,
                               "name": advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? "",
                               "local_name": advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "",
                               "cached_name": peripheral.name ?? "",
                               "rssi": rssi.intValue, "manufacturer_hex": hex(manufacturer),
                               "services": services, "service_data": data,
                               "connectable": advertisementData[CBAdvertisementDataIsConnectable] as? Bool ?? false])
    }
}

let recorder = Recorder()
let initial = ProcessInfo.processInfo.systemUptime
while true {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    let now = ProcessInfo.processInfo.systemUptime
    if let started = recorder.scanningSince, now - started >= Double(seconds) { break }
    if recorder.scanningSince == nil, now - initial >= 30 { fail("No scan started within 30 seconds. Check Bluetooth permission.") }
}
recorder.central.stopScan()
emit("summary", ["label": label, "packets": recorder.packets, "devices": recorder.devices.count,
                 "counts": Dictionary(uniqueKeysWithValues: recorder.counts.map { ($0.key.uuidString, $0.value) })])
