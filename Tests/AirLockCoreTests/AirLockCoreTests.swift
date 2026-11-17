import Testing
@testable import AirLockCore

// Bytes recorded from real AirPods Pro (product 0x2024) on 2026-11-16, worn, 90%/100%.
let worn: [UInt8] = [0x4C, 0x00, 0x07, 0x19, 0x01, 0x24, 0x20, 0x0B, 0x9A, 0x8F, 0x11, 0x00]

struct AdvertTests {
    @Test func parsesRecordedPacket() throws {
        let a = try #require(Advert(manufacturerData: worn))
        #expect(a.productID == 0x2024)
        #expect(a.batteryA == 9 && a.batteryB == 10)
        #expect(a.inEar)
    }

    @Test func rejectsOtherPackets() {
        #expect(Advert(manufacturerData: [0x4C, 0x00, 0x10, 0x05, 0x01]) == nil)  // other Apple type
        #expect(Advert(manufacturerData: [0x06, 0x00, 0x07, 0x19, 0x01, 0x24, 0x20, 0x0B, 0x9A]) == nil)  // not Apple
        #expect(Advert(manufacturerData: Array(worn.prefix(8))) == nil)  // too short
    }

    @Test func notInEarWhenBothBitsClear() throws {
        var bytes = worn
        bytes[7] = 0x01
        #expect(try #require(Advert(manufacturerData: bytes)).inEar == false)
    }
}

struct TargetTests {
    let advert = Advert(manufacturerData: worn)!

    @Test func matchesSameModelAndBattery() {
        #expect(Target(name: "a", productID: 0x2024, left: 98, right: 100).matches(advert))
        #expect(Target(name: "a", productID: 0x2024, left: 100, right: 98).matches(advert))  // other order
        #expect(Target(name: "a", productID: 0x2024, left: nil, right: nil).matches(advert))
    }

    @Test func rejectsOtherModelOrBattery() {
        #expect(!Target(name: "a", productID: 0x2014, left: 98, right: 100).matches(advert))
        #expect(!Target(name: "a", productID: 0x2024, left: 60, right: 70).matches(advert))
    }
}

struct DeciderTests {
    /// Feeds one reading per second from `from` to `to` (inclusive) and returns every event.
    func run(_ d: inout Decider, from: Int, to: Int, rssi: Int?, inEar: Bool = true) -> [Event] {
        var events: [Event] = []
        for s in from...to {
            let t = Double(s)
            if let rssi, let e = d.observe(rssi: rssi, inEar: inEar, at: t) { events.append(e) }
            if let e = d.tick(at: t) { events.append(e) }
        }
        return events
    }

    @Test func armsNearAndLocksAfterSilence() {
        var d = Decider()
        do { let e = run(&d, from: 0, to: 5, rssi: -56); #expect(e == [.armed]) }
        do { let e = run(&d, from: 6, to: 12, rssi: nil); #expect(e == []) }            // 7 s of silence
        do { let e = run(&d, from: 13, to: 13, rssi: nil); #expect(e == [.lock("no signal for 8 s")]) }
        do { let e = run(&d, from: 21, to: 60, rssi: nil); #expect(e == []) }            // locks once only
    }

    @Test func locksAfterWeakSignal() {
        var d = Decider()
        _ = run(&d, from: 0, to: 5, rssi: -56)
        let events = run(&d, from: 6, to: 30, rssi: -80)
        #expect(events.count == 1)
        if case .lock(let why) = events.first { #expect(why.contains("below -66 for 5 s")) } else { Issue.record("no lock") }
    }

    @Test func shortDipsDoNotLock() {
        var d = Decider()
        _ = run(&d, from: 0, to: 5, rssi: -56)
        // The desk recording had single readings down to -70 and gaps up to 5.4 s.
        do { let e = run(&d, from: 6, to: 8, rssi: -70); #expect(e == []) }
        do { let e = run(&d, from: 9, to: 14, rssi: nil); #expect(e == []) }
        do { let e = run(&d, from: 15, to: 40, rssi: -58); #expect(e == []) }
    }

    @Test func earbudsOutDisarms() {
        var d = Decider()
        _ = run(&d, from: 0, to: 5, rssi: -56)
        do { let e = run(&d, from: 6, to: 6, rssi: -56, inEar: false); #expect(e == [.disarmed("earbuds out")]) }
        do { let e = run(&d, from: 7, to: 60, rssi: nil); #expect(e == []) }             // case closed: no lock
    }

    @Test func doesNotArmWhenFar() {
        var d = Decider()
        do { let e = run(&d, from: 0, to: 10, rssi: -85); #expect(e == []) }
        do { let e = run(&d, from: 11, to: 40, rssi: nil); #expect(e == []) }
    }

    @Test func rearmsAfterComingBack() {
        var d = Decider()
        _ = run(&d, from: 0, to: 5, rssi: -56)
        _ = run(&d, from: 6, to: 20, rssi: nil)
        do { let e = run(&d, from: 21, to: 24, rssi: -55); #expect(e == []) }   // near, but not for 5 s yet
        do { let e = run(&d, from: 25, to: 27, rssi: -55); #expect(e.first == .armed) }
    }

    // Regression (log 2026-11-16 15:33): it re-armed 1 s after a lock while the user was still away.
    @Test func strongBlipAfterLockDoesNotRearm() {
        var d = Decider()
        _ = run(&d, from: 0, to: 5, rssi: -56)
        let locked = run(&d, from: 6, to: 30, rssi: -80)
        #expect(locked.count == 1)
        do { let e = run(&d, from: 31, to: 31, rssi: -55); #expect(e == []) }
        do { let e = run(&d, from: 32, to: 60, rssi: -78); #expect(e == []) }
    }
}

// Real readings from the walk test on 2026-11-16 (AirPods Pro worn): desk 0–20 s,
// 3 m 20–40 s, next room 40–60 s (no packets), back at the desk from about 75 s.
let walk: [(Double, Int)] = [(0.1, -55), (0.5, -63), (0.7, -57), (1.6, -70), (1.8, -68), (2.2, -67), (2.4, -60), (2.5, -57), (3.3, -57), (4.0, -49), (4.4, -54), (5.7, -70), (6.1, -63), (6.3, -59), (6.4, -60), (7.6, -53), (7.9, -57), (8.1, -58), (8.3, -53), (9.2, -62), (9.6, -62), (9.8, -62), (10.0, -58), (10.2, -54), (10.3, -55), (11.5, -59), (11.8, -59), (13.3, -51), (16.3, -56), (17.8, -54), (20.2, -60), (21.7, -53), (23.2, -64), (25.6, -72), (28.0, -68), (30.5, -83), (32.0, -67), (35.9, -65), (65.0, -80), (66.5, -76), (70.4, -70), (71.9, -68), (77.3, -56), (78.8, -57), (80.3, -61), (81.9, -61), (82.1, -60), (82.3, -56), (82.5, -55), (84.0, -55), (84.2, -51), (85.1, -52), (85.9, -55), (86.0, -54), (87.5, -56), (87.9, -57), (88.1, -56), (89.0, -59), (89.4, -64), (89.8, -55), (89.9, -52), (91.1, -52), (91.2, -53), (91.4, -53), (91.6, -53), (92.9, -50), (93.1, -51), (93.3, -51), (94.2, -49), (94.4, -49)]

struct RecordedWalkTests {
    @Test func locksOnlyAfterLeavingTheDesk() {
        // The app's default AirPods settings, not the bare Rules() defaults.
        var d = Decider(rules: LockSettings().rules)
        var locks: [Double] = []
        var arms: [Double] = []
        var next = 0
        for step in 0...(95 * 4) {
            let t = Double(step) / 4
            while next < walk.count, walk[next].0 <= t {
                if d.observe(rssi: walk[next].1, inEar: true, at: walk[next].0) == .armed { arms.append(walk[next].0) }
                next += 1
            }
            if case .lock = d.tick(at: t) { locks.append(t) }
        }
        #expect(arms.first.map { $0 <= 20 } == true)                 // arms at the desk before you leave
        #expect(arms.count == 2)                                    // and again after you come back
        #expect(locks.count == 1)                                   // no lock at the desk, before or after
        #expect(locks.allSatisfy { $0 > 20 && $0 <= 35 })           // at the 3 m spot, before the next room
    }
}

struct PeerPickerTests {
    @Test func followsOnePeerAndHandsOverAfterSilence() {
        var p = PeerPicker<String>()
        do { let ok = p.accept("far", rssi: -85, at: 0); #expect(!ok) }    // too weak to start with
        do { let ok = p.accept("mine", rssi: -55, at: 1); #expect(ok) }
        do { let ok = p.accept("other", rssi: -50, at: 2); #expect(!ok) }  // keeps the current peer
        do { let ok = p.accept("mine", rssi: -56, at: 3); #expect(ok) }
        do { let ok = p.accept("rotated", rssi: -57, at: 9); #expect(ok) } // current silent > 5 s
        #expect(p.current == "rotated")
    }
}
