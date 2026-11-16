import Foundation

public struct Rules: Equatable, Sendable {
    /// Lock when no advertisement arrives for this long (seconds).
    public var silence: TimeInterval = 8
    /// Lock when the median signal stays below this (dBm) ...
    public var weakRSSI = -66
    /// ... for this long (seconds).
    public var weakFor: TimeInterval = 5
    /// The median covers this many seconds of readings.
    public var window: TimeInterval = 5
    /// Arm only after the median stays at or above this (dBm) ...
    public var nearRSSI = -62
    /// ... for this long (seconds): you are back near the Mac, not passing a strong reading.
    public var nearFor: TimeInterval = 5

    public init() {}
}

public enum Event: Equatable, Sendable {
    case armed
    case disarmed(String)
    case lock(String)
}

/// Turns signal readings into lock decisions. Times are seconds on any steady clock.
/// It locks at most once per arming: after a lock it waits until you are near again.
public struct Decider: Sendable {
    public var rules: Rules
    public private(set) var armed = false
    private var readings: [(t: TimeInterval, rssi: Int)] = []
    private var lastSeen: TimeInterval?
    private var weakSince: TimeInterval?
    private var nearSince: TimeInterval?

    public init(rules: Rules = Rules()) { self.rules = rules }

    /// Median of the readings in the last `window` seconds before `now`.
    public func median(at now: TimeInterval) -> Int? {
        let recent = readings.filter { now - $0.t <= rules.window }.map(\.rssi).sorted()
        return recent.isEmpty ? nil : recent[recent.count / 2]
    }

    public mutating func observe(rssi: Int, inEar: Bool, at t: TimeInterval) -> Event? {
        lastSeen = t
        readings.append((t, rssi))
        readings.removeAll { t - $0.t > rules.window }
        if !inEar {
            // Earbuds out or in the case: silence that follows is not you walking away.
            weakSince = nil
            nearSince = nil
            if armed { armed = false; return .disarmed("earbuds out") }
            return nil
        }
        guard !armed else { return nil }
        if let m = median(at: t), m >= rules.nearRSSI {
            let since = nearSince ?? t
            nearSince = since
            if t - since >= rules.nearFor {
                armed = true
                weakSince = nil
                nearSince = nil
                return .armed
            }
        } else {
            nearSince = nil
        }
        return nil
    }

    public mutating func tick(at t: TimeInterval) -> Event? {
        guard armed, let lastSeen else { return nil }
        if t - lastSeen >= rules.silence {
            return lock("no signal for \(Int(t - lastSeen)) s")
        }
        guard let m = median(at: t) else { return nil }
        if m < rules.weakRSSI {
            let since = weakSince ?? t
            weakSince = since
            if t - since >= rules.weakFor {
                return lock("signal \(m) dBm, below \(rules.weakRSSI) for \(Int(t - since)) s")
            }
        } else {
            weakSince = nil
        }
        return nil
    }

    private mutating func lock(_ reason: String) -> Event {
        armed = false
        weakSince = nil
        return .lock(reason)
    }
}

/// Follows one advertising peer. Bluetooth LE addresses rotate, so a new matching
/// peer replaces the current one when the current one has been silent for `handover` seconds.
public struct PeerPicker<ID: Hashable & Sendable>: Sendable {
    public var handover: TimeInterval = 5
    public var startRSSI = -70
    public private(set) var current: ID?
    private var lastSeen: TimeInterval = 0

    public init() {}

    /// Returns true when this advertisement belongs to the followed peer.
    public mutating func accept(_ peer: ID, rssi: Int, at t: TimeInterval) -> Bool {
        if peer == current || (current == nil && rssi >= startRSSI) || (current != nil && t - lastSeen > handover) {
            current = peer
            lastSeen = t
            return true
        }
        return false
    }

    public mutating func reset() { current = nil }
}
