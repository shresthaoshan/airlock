import AirLockCore
import Foundation

enum SystemInfo {
    /// The first connected Apple headphones that System Information lists, or nil.
    static func connectedAirPods() -> Target? {
        guard let out = run("/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json"]),
              let json = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
              let root = (json["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = root["device_connected"] as? [[String: [String: Any]]] else { return nil }
        for entry in connected {
            for (name, info) in entry {
                guard info["device_vendorID"] as? String == "0x004C",
                      info["device_minorType"] as? String == "Headphones",
                      let pid = (info["device_productID"] as? String).flatMap({ UInt16($0.dropFirst(2), radix: 16) })
                else { continue }
                func percent(_ key: String) -> Int? {
                    (info[key] as? String).flatMap { Int($0.replacingOccurrences(of: "%", with: "")) }
                }
                return Target(name: name, productID: pid,
                              left: percent("device_batteryLevelLeft"), right: percent("device_batteryLevelRight"))
            }
        }
        return nil
    }

    /// True when macOS asks for the password as soon as the display sleeps.
    static func screenLockIsImmediate() -> Bool {
        guard let out = run("/usr/sbin/sysadminctl", ["-screenLock", "status"], stderr: true) else { return false }
        return String(decoding: out, as: UTF8.self).contains("immediate")
    }

    static func run(_ path: String, _ args: [String], stderr: Bool = false) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = stderr ? pipe : FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return data
    }
}

enum Locker {
    /// Sleeps the display. With "require password immediately" on, this locks the Mac.
    static func lock() {
        _ = SystemInfo.run("/usr/bin/pmset", ["displaysleepnow"])
    }
}

enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AirLock.log")
    private static let format: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func write(_ line: String) {
        let text = "\(format.string(from: Date())) \(line)\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile()
            h.write(Data(text.utf8))
            try? h.close()
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }
}
