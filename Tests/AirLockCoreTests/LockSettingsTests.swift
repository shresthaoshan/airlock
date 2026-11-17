import Foundation
import Testing
@testable import AirLockCore

struct LockSettingsTests {
    @Test func normalizesThresholdAndDelay() {
        let old = LockSettings(threshold: -66, delay: 5)
        #expect(old.threshold == -70)
        #expect(old.delay == 5)
        #expect(LockSettings(threshold: Int.min, delay: -1).threshold == -120)
        #expect(LockSettings(threshold: Int.max, delay: 31).threshold == -20)
        #expect(LockSettings(threshold: -20, delay: -1).delay == 0)
        #expect(LockSettings(threshold: -120, delay: 31).delay == 30)
    }

    @Test func savesAndLoadsUsingTheExistingKeys() throws {
        let name = "AirLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(LockSettings(defaults: defaults) == LockSettings(threshold: -60, delay: 5))
        defaults.set(-66, forKey: "weakRSSI")
        defaults.set(30, forKey: "weakSeconds")
        defaults.set(1, forKey: "silenceSeconds")
        defaults.set(-62, forKey: "nearRSSI")
        let loaded = LockSettings(defaults: defaults)
        #expect(loaded.threshold == -70)
        #expect(loaded.rules.silence == 33)
        #expect(loaded.rules.nearRSSI == -68)
        LockSettings(threshold: -100, delay: 0).save(to: defaults)
        #expect(LockSettings(defaults: defaults) == LockSettings(threshold: -100, delay: 0))
    }

    @Test func rejectsInvalidSavedValues() throws {
        let name = "AirLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("invalid", forKey: "weakRSSI")
        defaults.set(Double.nan, forKey: "weakSeconds")
        #expect(LockSettings(defaults: defaults) == LockSettings())
        defaults.set(-9999, forKey: "weakRSSI")
        defaults.set(9999, forKey: "weakSeconds")
        #expect(LockSettings(defaults: defaults) == LockSettings(threshold: -120, delay: 30))
        defaults.set(-64.6, forKey: "weakRSSI")
        #expect(LockSettings(defaults: defaults).threshold == -60)
    }

    @Test(arguments: [0, 5, 30]) func noSignalLocksThreeSecondsAfterConfiguredDelay(_ delay: Int) {
        var d = Decider(rules: LockSettings(threshold: -70, delay: delay).rules)
        for t in 0...5 { _ = d.observe(rssi: -55, inEar: true, at: Double(t)) }
        #expect(d.armed)
        #expect(d.tick(at: Double(5 + delay + 2)) == nil)
        #expect(d.tick(at: Double(5 + delay + 3)) == .lock("no signal for \(delay + 3) s"))
        #expect(d.tick(at: 100) == nil)
    }

    @Test(arguments: [0, 30]) func weakSignalUsesConfiguredDelay(_ delay: Int) {
        var d = Decider(rules: LockSettings(threshold: -70, delay: delay).rules)
        for t in 0...5 { _ = d.observe(rssi: -55, inEar: true, at: Double(t)) }
        var lockTime: Int?
        for t in 6...(8 + delay) {
            _ = d.observe(rssi: -90, inEar: true, at: Double(t))
            if case .lock = d.tick(at: Double(t)) { lockTime = t }
        }
        // The 5-second median first becomes weak at t=9 (four weak readings).
        #expect(lockTime == nil)
        _ = d.observe(rssi: -90, inEar: true, at: Double(9 + delay))
        if case .lock = d.tick(at: Double(9 + delay)) {} else { Issue.record("No weak signal lock") }
    }

    @Test(arguments: [-120, -20]) func armsAtBothSliderEndpoints(_ threshold: Int) {
        var d = Decider(rules: LockSettings(threshold: threshold, delay: 5).rules)
        for t in 0...5 { _ = d.observe(rssi: threshold + 2, inEar: true, at: Double(t)) }
        #expect(d.armed)
    }
}

struct LiveSignalTests {
    @Test func expiresAndClearsTheDeviceAndSignalTogether() {
        var signal = LiveSignal()
        #expect(signal.value(at: 0, timeout: 8) == nil)
        signal.record(name: "My AirPods", rssi: -55, at: 10)
        #expect(signal.value(at: 17.9, timeout: 8)?.name == "My AirPods")
        #expect(signal.value(at: 17.9, timeout: 8)?.rssi == -55)
        #expect(signal.value(at: 18, timeout: 8) == nil)
        signal.record(name: "New AirPods", rssi: -65, at: 20)
        signal.clear()
        #expect(signal.value(at: 20, timeout: 8) == nil)
    }
}
