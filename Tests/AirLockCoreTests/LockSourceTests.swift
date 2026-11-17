import Foundation
import Testing
@testable import AirLockCore

struct LockSourceTests {
    @Test func savesExactPhoneIdentityAndMode() throws {
        let suite = "AirLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let phone = PhoneDevice(id: UUID(), name: "Desk iPhone")
        var source = LockSource(defaults: defaults)
        #expect(source.device == .airPods)
        #expect(source.phone == nil)
        source.device = .iPhone
        source.phone = phone
        source.save(to: defaults)
        let restored = LockSource(defaults: defaults)
        #expect(restored == source)
        #expect(restored.acceptsPhone(phone.id))
        #expect(!restored.acceptsPhone(UUID()))
        source.device = .airPods
        #expect(!source.acceptsPhone(phone.id))
        source.device = .iPhone
        source.phone = nil
        #expect(!source.acceptsPhone(phone.id))
        source.save(to: defaults)
        #expect(LockSource(defaults: defaults).phone == nil)
    }

    @Test func ignoresInvalidStoredIdentity() throws {
        let suite = "AirLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("unknown", forKey: "lockDevice")
        defaults.set("not-a-uuid", forKey: "iphoneIdentifier")
        defaults.set("Same Name", forKey: "iphoneName")
        let source = LockSource(defaults: defaults)
        #expect(source.device == .airPods)
        #expect(source.phone == nil)
    }

    @Test func storesIndependentProfilesAndPreservesAirPodsSettings() throws {
        let suite = "AirLockTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        LockSettings(threshold: -80, delay: 2).save(to: defaults)
        #expect(LockSettings(defaults: defaults, device: .iPhone) == LockSettings(threshold: -60, delay: 10))
        LockSettings(threshold: -50, delay: 30).save(to: defaults, device: .iPhone)
        #expect(LockSettings(defaults: defaults) == LockSettings(threshold: -80, delay: 2))
        #expect(LockSettings(defaults: defaults, device: .iPhone) == LockSettings(threshold: -50, delay: 30))
        #expect(LockSettings(defaults: defaults, device: .iPhone).rules.silence == 33)
        defaults.set("invalid", forKey: "iphoneWeakRSSI")
        defaults.set(Double.nan, forKey: "iphoneWeakSeconds")
        #expect(LockSettings(defaults: defaults, device: .iPhone) == LockSettings(threshold: -60, delay: 10))
    }
}
