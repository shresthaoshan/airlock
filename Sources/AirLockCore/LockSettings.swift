import Foundation

public struct LockSettings: Equatable, Sendable {
    public let threshold: Int
    public let delay: Int

    public init(threshold: Int = -70, delay: Int = 5) {
        self.threshold = Int((Double(min(-20, max(-120, threshold))) / 10).rounded()) * 10
        self.delay = min(30, max(0, delay))
    }

    public init(defaults: UserDefaults) {
        func number(_ key: String, fallback: Double, range: ClosedRange<Double>, step: Double = 1) -> Int {
            guard let value = defaults.object(forKey: key) as? NSNumber,
                  value.doubleValue.isFinite else { return Int(fallback) }
            let bounded = min(range.upperBound, max(range.lowerBound, value.doubleValue))
            return Int((bounded / step).rounded() * step)
        }
        self.init(threshold: number("weakRSSI", fallback: -70, range: -120 ... -20, step: 10),
                  delay: number("weakSeconds", fallback: 5, range: 0 ... 30))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(threshold, forKey: "weakRSSI")
        defaults.set(delay, forKey: "weakSeconds")
    }

    public var rules: Rules {
        var rules = Rules()
        rules.weakRSSI = threshold
        rules.weakFor = Double(delay)
        rules.silence = Double(delay + 3)
        rules.nearRSSI = threshold + 4
        return rules
    }
}

/// A displayed signal must expire even when automatic locking is disabled.
public struct LiveSignal: Sendable {
    private var sample: (name: String, rssi: Int, time: TimeInterval)?

    public init() {}

    public mutating func record(name: String, rssi: Int, at time: TimeInterval) {
        sample = (name, rssi, time)
    }

    public func value(at time: TimeInterval, timeout: TimeInterval) -> (name: String, rssi: Int)? {
        guard let sample, time - sample.time < timeout else { return nil }
        return (sample.name, sample.rssi)
    }

    public mutating func clear() { sample = nil }
}
