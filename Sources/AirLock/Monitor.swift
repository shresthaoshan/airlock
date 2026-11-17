import AirLockCore
import CoreBluetooth
import Foundation

/// Follows the selected AirPods or iPhone through Bluetooth LE advertisements and
/// locks the Mac when the rules say you walked away. All work runs on the main queue.
final class Monitor: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager!
    private var decider = Decider()
    private var picker = PeerPicker<UUID>()
    private var target: Target?
    private var observedPhones: [UUID: (phone: PhoneDevice, seen: TimeInterval)] = [:]
    private var followedPhone: CBPeripheral?
    private var liveSignal = LiveSignal()
    private var refreshingTarget = false
    private var lastLog: TimeInterval = 0
    private var tickTimer: Timer?
    private var targetTimer: Timer?
    private(set) var settings = LockSettings(defaults: .standard)
    private(set) var source = LockSource(defaults: .standard)
    var enabled = true {
        didSet {
            decider = Decider(rules: settings.rules)
            onChange?()
        }
    }
    var onChange: (() -> Void)?

    override init() {
        super.init()
        settings = LockSettings(defaults: .standard, device: source.device)
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

    var nearbyPhones: [PhoneDevice] {
        observedPhones.values.filter { now - $0.seen <= 30 }.map(\.phone).sorted {
            if $0.name == $1.name { return $0.id.uuidString < $1.id.uuidString }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    func selectDevice(_ device: LockDevice) {
        guard source.device != device else { return }
        source.device = device
        source.save(to: .standard)
        settings = LockSettings(defaults: .standard, device: device)
        resetDecisions()
        Log.write("lock source \(device.rawValue)")
        onChange?()
    }

    func selectPhone(_ phone: PhoneDevice?) {
        guard source.phone != phone else { return }
        source.phone = phone
        source.save(to: .standard)
        if source.device == .iPhone { resetDecisions() }
        Log.write("selected iPhone \(phone?.name ?? "none")")
        onChange?()
    }

    private func resetDecisions() {
        decider = Decider(rules: settings.rules)
        liveSignal.clear()
        picker.reset()
        picker.startRSSI = min(-70, settings.threshold - 4)
        followedPhone = nil
    }

    func applySettings(_ settings: LockSettings) {
        guard settings != self.settings else { return }
        self.settings = settings
        settings.save(to: .standard, device: source.device)
        resetDecisions()
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
                    if self.source.device == .airPods { self.resetDecisions() }
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
            observedPhones.removeAll()
            followedPhone = nil
        }
        onChange?()
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi: NSNumber) {
        let r = rssi.intValue
        guard r < 0, r > -127 else { return }
        let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let bytes = data.map { [UInt8]($0) } ?? []
        let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
        if bytes.count >= 2, bytes[0] == 0x4C, bytes[1] == 0,
           !(bytes.count > 2 && bytes[2] == 0x07), !name.isEmpty {
            let phone = PhoneDevice(id: peripheral.identifier, name: name)
            let changed = observedPhones[phone.id]?.phone != phone
            observedPhones[phone.id] = (phone, now)
            if changed { onChange?() }
        }

        if source.device == .iPhone {
            guard source.acceptsPhone(peripheral.identifier), let phone = source.phone else { return }
            followedPhone = peripheral
            liveSignal.record(name: phone.name, rssi: r, at: now)
            if enabled, let event = decider.observe(rssi: r, inEar: true, at: now) { handle(event) }
            onChange?()
            return
        }

        guard let target,
              let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let advert = Advert(manufacturerData: [UInt8](data)), target.matches(advert) else { return }
        let before = picker.current
        guard picker.accept(peripheral.identifier, rssi: r, at: now) else { return }
        if before != nil, before != picker.current { Log.write("peer changed (address rotated)") }
        liveSignal.record(name: target.name, rssi: r, at: now)
        if enabled, let event = decider.observe(rssi: r, inEar: advert.inEar, at: now) { handle(event) }
        onChange?()
    }

    // MARK: Rules

    private func tick() {
        observedPhones = observedPhones.filter { now - $0.value.seen <= 30 }
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
