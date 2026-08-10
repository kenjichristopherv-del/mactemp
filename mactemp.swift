// mactemp — read Apple Silicon thermal sensors without sudo.
//
// Sensors come from IOKit's HID event system, the same source Activity Monitor
// and third-party tools use. The symbols are private, so they are resolved at
// runtime with dlsym rather than linked against.

import Foundation
import IOKit

private typealias ClientCreate = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
private typealias ClientSetMatching = @convention(c) (AnyObject?, CFDictionary?) -> Int32
private typealias ClientCopyServices = @convention(c) (AnyObject?) -> CFArray?
private typealias ServiceCopyProperty = @convention(c) (AnyObject?, CFString) -> CFTypeRef?
private typealias ServiceCopyEvent = @convention(c) (AnyObject?, Int64, Int32, Int64) -> AnyObject?
private typealias EventGetFloatValue = @convention(c) (AnyObject?, Int32) -> Double

// kIOHIDEventTypeTemperature. The value field is the type shifted into the
// high half of the field id.
private let temperatureEvent: Int64 = 15
private let temperatureField = Int32(15 << 16)

// PrimaryUsagePage 0xff00 / PrimaryUsage 5 selects temperature sensors only.
private let sensorUsagePage = 0xff00
private let sensorUsage = 5

struct Reading {
    let name: String
    let celsius: Double
}

func readSensors() -> [Reading] {
    guard let iokit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW) else {
        return []
    }
    func symbol<T>(_ name: String) -> T? {
        guard let p = dlsym(iokit, name) else { return nil }
        return unsafeBitCast(p, to: T.self)
    }
    guard
        let create: ClientCreate = symbol("IOHIDEventSystemClientCreate"),
        let setMatching: ClientSetMatching = symbol("IOHIDEventSystemClientSetMatching"),
        let copyServices: ClientCopyServices = symbol("IOHIDEventSystemClientCopyServices"),
        let copyProperty: ServiceCopyProperty = symbol("IOHIDServiceClientCopyProperty"),
        let copyEvent: ServiceCopyEvent = symbol("IOHIDServiceClientCopyEvent"),
        let floatValue: EventGetFloatValue = symbol("IOHIDEventGetFloatValue"),
        let client = create(kCFAllocatorDefault)?.takeRetainedValue()
    else { return [] }

    let match: [String: Any] = ["PrimaryUsagePage": sensorUsagePage, "PrimaryUsage": sensorUsage]
    _ = setMatching(client, match as CFDictionary)
    guard let services = copyServices(client) as? [AnyObject] else { return [] }

    return services.compactMap { service in
        guard
            let name = copyProperty(service, "Product" as CFString) as? String,
            let event = copyEvent(service, temperatureEvent, 0, 0)
        else { return nil }
        let value = floatValue(event, temperatureField)
        // Unpopulated sensors report small negatives; nothing in this machine
        // legitimately reads below freezing or above 130 C.
        guard value > 0, value < 130 else { return nil }
        return Reading(name: name, celsius: value)
    }
}

func mean(_ xs: [Double]) -> Double? {
    guard !xs.isEmpty else { return nil }
    return xs.reduce(0, +) / Double(xs.count)
}

// "PMU tdie3" / "PMU2 tdie7" are the SoC die sensors — the number that matters.
// The "tdev" siblings track the surrounding board and run cooler and noisier.
let readings = readSensors()
let die = readings.filter { $0.name.contains("tdie") }.map(\.celsius)
let battery = readings.filter { $0.name.lowercased().contains("battery") }.map(\.celsius)
let storage = readings.filter { $0.name.contains("NAND") }.map(\.celsius)

let thermalState: String
switch ProcessInfo.processInfo.thermalState {
case .nominal:  thermalState = "nominal"
case .fair:     thermalState = "fair"
case .serious:  thermalState = "serious"
case .critical: thermalState = "critical"
@unknown default: thermalState = "unknown"
}

func field(_ key: String, _ value: Double?) -> String? {
    guard let value else { return nil }
    return "\"\(key)\":\(String(format: "%.1f", value))"
}

if CommandLine.arguments.contains("--list") {
    for r in readings.sorted(by: { $0.name < $1.name }) {
        let label = r.name.padding(toLength: max(24, r.name.count), withPad: " ", startingAt: 0)
        print("\(label) \(String(format: "%6.2f", r.celsius)) C")
    }
    exit(0)
}

let fields = [
    field("die_max", die.max()),
    field("die_avg", mean(die)),
    field("battery", mean(battery)),
    field("storage", storage.max()),
    "\"thermal_state\":\"\(thermalState)\"",
    "\"sensors\":\(readings.count)",
].compactMap { $0 }

print("{\(fields.joined(separator: ","))}")
