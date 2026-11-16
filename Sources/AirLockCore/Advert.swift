/// One AirPods "proximity pairing" advertisement: Apple manufacturer data, type 0x07.
/// Layout (bytes): 4C 00 | 07 | length | 01 | product ID (little endian, 2) | status | battery | ...
public struct Advert: Equatable, Sendable {
    public let productID: UInt16
    public let status: UInt8
    /// Battery of each bud in tens of percent (0...10), nil when unknown. The order
    /// (left/right) depends on which bud sends, so matching accepts both orders.
    public let batteryA: Int?
    public let batteryB: Int?

    /// At least one bud is in an ear (status bits 0x02 and 0x08).
    public var inEar: Bool { status & 0x0A != 0 }

    public init?(manufacturerData m: [UInt8]) {
        guard m.count >= 9, m[0] == 0x4C, m[1] == 0x00, m[2] == 0x07 else { return nil }
        productID = UInt16(m[5]) | UInt16(m[6]) << 8
        status = m[7]
        func level(_ n: UInt8) -> Int? { n <= 10 ? Int(n) : nil }
        batteryA = level(m[8] >> 4)
        batteryB = level(m[8] & 0x0F)
    }
}

/// The AirPods connected to this Mac, as System Information reports them.
public struct Target: Equatable, Sendable {
    public let name: String
    public let productID: UInt16
    public let left: Int?   // percent
    public let right: Int?  // percent

    public init(name: String, productID: UInt16, left: Int?, right: Int?) {
        self.name = name
        self.productID = productID
        self.left = left
        self.right = right
    }

    /// Same model, and battery levels within 10 percent in either bud order.
    public func matches(_ a: Advert) -> Bool {
        guard a.productID == productID else { return false }
        let want = [left, right].map { $0.map { min($0 / 10, 10) } }
        func close(_ x: Int?, _ y: Int?) -> Bool {
            guard let x, let y else { return true }
            return abs(x - y) <= 1
        }
        return (close(want[0], a.batteryA) && close(want[1], a.batteryB))
            || (close(want[0], a.batteryB) && close(want[1], a.batteryA))
    }
}
