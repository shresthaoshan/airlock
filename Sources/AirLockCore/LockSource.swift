import Foundation

public enum LockDevice: String, Sendable {
    case airPods
    case iPhone
}

public struct PhoneDevice: Equatable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }

    /// AirPods and Beats also send named Apple advertisements; they are not iPhone choices.
    public static func isCandidate(name: String, headphones: String?) -> Bool {
        guard !name.isEmpty, name != headphones else { return false }
        return !["airpods", "beats"].contains { name.lowercased().contains($0) }
    }
}

public struct LockSource: Equatable, Sendable {
    public var device: LockDevice
    public var phone: PhoneDevice?

    public init(device: LockDevice = .airPods, phone: PhoneDevice? = nil) {
        self.device = device
        self.phone = phone
    }

    public init(defaults: UserDefaults) {
        device = defaults.string(forKey: "lockDevice").flatMap(LockDevice.init(rawValue:)) ?? .airPods
        if let value = defaults.string(forKey: "iphoneIdentifier"), let id = UUID(uuidString: value) {
            phone = PhoneDevice(id: id, name: defaults.string(forKey: "iphoneName") ?? "iPhone")
        }
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(device.rawValue, forKey: "lockDevice")
        defaults.set(phone?.id.uuidString, forKey: "iphoneIdentifier")
        defaults.set(phone?.name, forKey: "iphoneName")
    }

    public func acceptsPhone(_ id: UUID) -> Bool {
        device == .iPhone && phone?.id == id
    }
}
