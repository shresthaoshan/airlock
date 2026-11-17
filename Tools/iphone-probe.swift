// Feasibility probe only. This tool does not call AirLock or lock the screen.
// Build: swiftc Tools/iphone-probe.swift -o .build/iphone-probe
// List:  .build/iphone-probe --list
// Scan:  .build/iphone-probe --inquire (keep the iPhone Bluetooth settings open)
// Probe: .build/iphone-probe --device 'Exact paired name' --seconds 60 --connect
import Foundation
import IOBluetooth

func emit(_ event: String, _ fields: [String: Any] = [:]) {
    var record = fields
    record["event"] = event
    record["time"] = ISO8601DateFormatter().string(from: Date())
    let data = try! JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    fflush(stdout)
}

func fail(_ message: String) -> Never {
    emit("error", ["message": message])
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
if args == ["--inquire"] {
    final class Discovery: NSObject, IOBluetoothDeviceInquiryDelegate {
        var complete = false
        var count = 0
        func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
            count += 1
            emit("discovered_device", ["name": device.name ?? "Unnamed", "address": device.addressString ?? "",
                                       "paired": device.isPaired()])
        }
        func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
            complete = true
            emit("inquiry_complete", ["status": Int(error), "aborted": aborted, "devices": count])
        }
    }
    let observer = Discovery()
    guard let inquiry = IOBluetoothDeviceInquiry(delegate: observer) else {
        fail("Could not create a Bluetooth inquiry.")
    }
    inquiry.inquiryLength = 15
    inquiry.updateNewDeviceNames = false
    let status = inquiry.start()
    emit("inquiry_start", ["status": Int(status)])
    guard status == kIOReturnSuccess else { exit(1) }
    let deadline = ProcessInfo.processInfo.systemUptime + 30
    while !observer.complete, ProcessInfo.processInfo.systemUptime < deadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.2))
    }
    if !observer.complete {
        inquiry.stop()
        emit("inquiry_timeout", ["devices": observer.count])
    }
    exit(0)
}
if args.contains("--help") {
    print("Usage: iphone-probe --list | --inquire | --device <exact paired name or address> [--seconds 60] [--connect]")
    exit(0)
}
var selected: String?
var duration = 60
var connect = false
var list = args.isEmpty
var i = 0
while i < args.count {
    switch args[i] {
    case "--list": list = true
    case "--connect": connect = true
    case "--device", "--seconds":
        let option = args[i]
        i += 1
        guard i < args.count else { fail("Missing value for \(option)") }
        if option == "--device" { selected = args[i] }
        else {
            guard let value = Int(args[i]), (1...3600).contains(value) else {
                fail("Seconds must be a whole number from 1 to 3600.")
            }
            duration = value
        }
    default: fail("Unknown option: \(args[i])")
    }
    i += 1
}
var seenAddresses = Set<String>()
let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter {
    guard let address = $0.addressString else { return true }
    return seenAddresses.insert(address.lowercased()).inserted
}
if list {
    for device in devices {
        emit("paired_device", ["name": device.name ?? "Unnamed", "address": device.addressString ?? "",
                               "connected": device.isConnected()])
    }
    emit("list_summary", ["paired_count": devices.count])
    exit(0)
}
guard let selected else { fail("Use --list, then specify --device with an exact paired name or address.") }
let matches = devices.filter { $0.name == selected || $0.addressString?.lowercased() == selected.lowercased() }
guard matches.count == 1, let device = matches.first else {
    fail("Found \(matches.count) paired matches. Use --list and select one exact address.")
}

final class Connection: NSObject {
    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        emit("connection_complete", ["status": Int(status), "connected": device?.isConnected() ?? false,
                                     "raw_rssi": device.map { Int($0.rawRSSI()) } ?? 127])
    }
}

let connection = Connection()
let start = ProcessInfo.processInfo.systemUptime
var attemptedConnection = false
var samples = 0
var validSamples = 0
var connectedSamples = 0
var longestGap: TimeInterval = 0
var lastValid = start
var minimum: Int?
var maximum: Int?
emit("start", ["device": device.name ?? "Unnamed", "seconds": duration, "connect": connect])
while ProcessInfo.processInfo.systemUptime - start < Double(duration) {
    let now = ProcessInfo.processInfo.systemUptime
    if connect, !device.isConnected(), !attemptedConnection {
        attemptedConnection = true
        let status = device.openConnection(connection, withPageTimeout: 8000, authenticationRequired: false)
        emit("connection_request", ["status": Int(status), "authentication_requested": false])
    }
    let connected = device.isConnected()
    let raw = Int(device.rawRSSI())
    let valid = connected && (-127...20).contains(raw)
    samples += 1
    if connected { connectedSamples += 1 }
    if valid {
        validSamples += 1
        longestGap = max(longestGap, now - lastValid)
        lastValid = now
        minimum = min(minimum ?? raw, raw)
        maximum = max(maximum ?? raw, raw)
    }
    emit("sample", ["elapsed_s": (now - start).rounded(), "connected": connected,
                    "raw_rssi": raw, "valid": valid])
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 1))
}
longestGap = max(longestGap, ProcessInfo.processInfo.systemUptime - lastValid)
var summary: [String: Any] = ["samples": samples, "connected_samples": connectedSamples,
                             "valid_samples": validSamples, "longest_gap_s": longestGap]
if let minimum, let maximum { summary["min_rssi"] = minimum; summary["max_rssi"] = maximum }
emit("summary", summary)
