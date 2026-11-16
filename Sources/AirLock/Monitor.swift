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
    private var liveSignal = LiveSignal()
    private var refreshingTarget = false
    private var lastLog: TimeInterval = 0
    private var tickTimer: Timer?
    private var targetTimer: Timer?
    private(set) var settings = LockSettings(defaults: .standard)
    var enabled = true {
        didSet {
            decider = Decider(rules: settings.rules)
            onChange?()
        }
    }
    var onChange: (() -> Void)?

    override init() {
        super.init()
        decider.rules = settings.rules
        picker.startRSSI = min(-70, settings.threshold - 4)
        central = CBCentralManager(delegate: self, queue: .main)
        refreshTarget()
        targetTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshTarget() }
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
    }

    var liveDevice: (name: String, rssi: Int)? {
        guard central.state == .poweredOn else { return nil }
        return liveSignal.value(at: now, timeout: settings.rules.silence)
    }

    func applySettings(_ settings: LockSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        settings.save(to: .standard)
        decider = Decider(rules: settings.rules)
        picker.startRSSI = min(-70, settings.threshold - 4)
        Log.write("settings threshold \(settings.threshold) dBm delay \(settings.delay) s")
        onChange?()
    }

    var armed: Bool { enabled && decider.armed }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Target from System Information

    func refreshTarget() {
        guard !refreshingTarget else { return }
        refreshingTarget = true
        DispatchQueue.global(qos: .utility).async {
            let found = SystemInfo.connectedAirPods()
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.refreshingTarget = false
                // Keep the last target during signal loss so the silence rule can lock.
                guard let found else { self.onChange?(); return }
                if found.name != self.target?.name || found.productID != self.target?.productID {
                    Log.write("target \(found.name) product 0x\(String(found.productID, radix: 16))")
                    self.picker.reset()
                    self.liveSignal.clear()
                    self.decider = Decider(rules: self.settings.rules)
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
        } else {
            liveSignal.clear()
            picker.reset()
        }
        onChange?()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        guard let target,
              let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let advert = Advert(manufacturerData: [UInt8](data)), target.matches(advert) else { return }
        let r = rssi.intValue
        guard r < 0, r > -127 else { return }  // 127 means "not available"
        let before = picker.current
        guard picker.accept(peripheral.identifier, rssi: r, at: now) else { return }
        if before != nil, before != picker.current { Log.write("peer changed (address rotated)") }
        liveSignal.record(name: target.name, rssi: r, at: now)
        if enabled, let event = decider.observe(rssi: r, inEar: advert.inEar, at: now) { handle(event) }
        onChange?()
    }

    // MARK: Rules

    private func tick() {
        if enabled, let event = decider.tick(at: now) { handle(event) }
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
            Locker.lock()
        }
        onChange?()
    }
}
