import AirLockCore
import CoreBluetooth
import Foundation

/// Finds your connected AirPods, follows their Bluetooth LE advertisements and
/// locks the Mac when the rules say you walked away. All work runs on the main queue.
final class Monitor: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private var decider = Decider()
    private var picker = PeerPicker<UUID>()
    private var target: Target?
    private var lastRSSI: Int?
    private var lastLog: TimeInterval = 0
    private var tickTimer: Timer?
    private var targetTimer: Timer?
    var enabled = true { didSet { if !enabled { decider = Decider(rules: decider.rules); picker.reset() } } }
    var onChange: (() -> Void)?

    override init() {
        super.init()
        decider.rules = Settings.rules()
        central = CBCentralManager(delegate: self, queue: .main)
        refreshTarget()
        targetTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshTarget() }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    var status: String {
        guard let target else { return "No AirPods connected yet" }
        let signal = lastRSSI.map { "\($0) dBm" } ?? "no signal"
        let state = !enabled ? "off" : decider.armed ? "armed" : "waiting until you are near"
        return "\(target.name) · \(signal) · \(state)"
    }

    var armed: Bool { enabled && decider.armed }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Target from System Information

    private func refreshTarget() {
        DispatchQueue.global(qos: .utility).async {
            let found = SystemInfo.connectedAirPods()
            DispatchQueue.main.async { [weak self] in
                guard let self, let found else { return }  // keep the last target when disconnected
                if found.name != self.target?.name || found.productID != self.target?.productID {
                    Log.write("target \(found.name) product 0x\(String(found.productID, radix: 16))")
                    self.picker.reset()
                }
                self.target = found
                self.onChange?()
            }
        }
    }

    // MARK: Bluetooth LE

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Log.write("bluetooth state \(central.state.rawValue)")
        if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard enabled, let target,
              let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let advert = Advert(manufacturerData: [UInt8](data)), target.matches(advert) else { return }
        let r = rssi.intValue
        guard r < 0, r > -127 else { return }  // 127 means "not available"
        let before = picker.current
        guard picker.accept(peripheral.identifier, rssi: r, at: now) else { return }
        if before != nil, before != picker.current { Log.write("peer changed (address rotated)") }
        lastRSSI = r
        if let event = decider.observe(rssi: r, inEar: advert.inEar, at: now) { handle(event) }
    }

    // MARK: Rules

    private func tick() {
        guard enabled else { return }
        if let event = decider.tick(at: now) { handle(event) }
        if now - lastLog >= 10 {
            lastLog = now
            Log.write("median \(decider.median(at: now).map(String.init) ?? "none") armed \(decider.armed)")
        }
        onChange?()
    }

    private func handle(_ event: Event) {
        switch event {
        case .armed: Log.write("armed")
        case .disarmed(let why): Log.write("disarmed: \(why)")
        case .lock(let why):
            Log.write("LOCK: \(why)")
            lastRSSI = nil
            Locker.lock()
        }
        onChange?()
    }
}
