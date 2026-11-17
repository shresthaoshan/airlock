// Diagnostic only: runs AirLockCore decisions but never locks the screen.
// Compile this file as main.swift together with Decider.swift and LockSettings.swift.
import CoreBluetooth
import Foundation

func emit(_ event: String, _ fields: [String: Any] = [:]) {
    var record = fields
    record["event"] = event
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    record["time"] = formatter.string(from: Date())
    let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}
func fail(_ message: String) -> Never {
    emit("error", ["message": message])
    exit(1)
}
let args = Array(CommandLine.arguments.dropFirst())
if args == ["--help"] {
    print("Usage: iphone-trial --device <Bluetooth UUID> [--seconds 1...600]")
    exit(0)
}
var target: UUID?
var seconds = 600
var index = 0
while index < args.count {
    let option = args[index]
    guard ["--device", "--seconds"].contains(option), index + 1 < args.count else { fail("Invalid argument.") }
    index += 1
    if option == "--device" {
        guard let id = UUID(uuidString: args[index]) else { fail("Device must be a Bluetooth UUID.") }
        target = id
    } else {
        guard let value = Int(args[index]), (1...600).contains(value) else { fail("Seconds must be 1...600.") }
        seconds = value
    }
    index += 1
}
guard let target else { fail("Specify --device with the confirmed Bluetooth UUID.") }
let settings = LockSettings(threshold: -60, delay: 10)

final class Trial: NSObject, CBCentralManagerDelegate {
    let targetID: UUID
    var central: CBCentralManager!
    var decider = Decider(rules: settings.rules)
    var started: TimeInterval?
    var peer: CBPeripheral?
    var samples = 0
    var arms = 0
    var lockDecisions = 0

    init(targetID: UUID) {
        self.targetID = targetID
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        emit("bluetooth_state", ["state": central.state.rawValue])
        if central.state == .poweredOn {
            started = started ?? ProcessInfo.processInfo.systemUptime
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            emit("scan_start", ["device_id": targetID.uuidString, "threshold": settings.threshold,
                                "weak_delay_s": settings.delay, "no_signal_delay_s": settings.delay + 3,
                                "arming_threshold": settings.rules.nearRSSI, "arming_delay_s": settings.rules.nearFor,
                                "seconds": seconds, "mode": "diagnostic_no_screen_lock"])
        } else if central.state == .unauthorized || central.state == .unsupported || central.state == .poweredOff {
            fail("Bluetooth scanning is unavailable. Check the Mac Bluetooth state and permission.")
        }
    }
    func record(_ event: Event, at now: TimeInterval) {
        let elapsed = now - (started ?? now)
        switch event {
        case .armed:
            arms += 1
            emit("armed", ["elapsed_s": elapsed])
        case .disarmed(let reason):
            emit("disarmed", ["elapsed_s": elapsed, "reason": reason])
        case .lock(let reason):
            lockDecisions += 1
            emit("would_lock", ["elapsed_s": elapsed, "reason": reason])
        }
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard peripheral.identifier == targetID, (-126 ... -1).contains(rssi.intValue) else { return }
        peer = peripheral
        samples += 1
        let now = ProcessInfo.processInfo.systemUptime
        if let event = decider.observe(rssi: rssi.intValue, inEar: true, at: now) { record(event, at: now) }
        emit("sample", ["elapsed_s": now - (started ?? now), "rssi": rssi.intValue,
                        "median_rssi": decider.median(at: now) as Any? ?? NSNull(), "armed": decider.armed])
    }
}
let trial = Trial(targetID: target)
let initial = ProcessInfo.processInfo.systemUptime
var lastTick: TimeInterval = 0
while true {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
    let now = ProcessInfo.processInfo.systemUptime
    if let started = trial.started, now - started >= Double(seconds) { break }
    if trial.started == nil, now - initial >= 30 { fail("No scan started within 30 seconds.") }
    if now - lastTick >= 1 {
        lastTick = now
        if let event = trial.decider.tick(at: now) { trial.record(event, at: now) }
    }
}
trial.central.stopScan()
emit("summary", ["samples": trial.samples, "arming_events": trial.arms, "would_lock_events": trial.lockDecisions,
                 "mode": "diagnostic_no_screen_lock"])
