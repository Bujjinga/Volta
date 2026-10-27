//
//  SmartBatteryReader.swift
//  Volta
//

import Foundation
import IOKit

/// Reads detailed battery telemetry from the `AppleSmartBattery` IORegistry entry.
///
/// This is the same source `ioreg -rn AppleSmartBattery` prints. The keys are
/// undocumented but have been stable across Intel and Apple Silicon for years.
enum SmartBatteryReader {
    struct Reading {
        var cycleCount: Int?
        var rawMaxCapacity: Int?
        var designCapacity: Int?
        var temperature: Double?
        var voltage: Int?
        var amperage: Int?
        var isCharging: Bool?
        var externalConnected: Bool?
        var fullyCharged: Bool?
        var adapterWatts: Int?
    }

    /// Returns `nil` when the Mac has no internal battery.
    static func read() -> Reading? {
        guard let properties = registryProperties() else { return nil }

        // Newer firmware (seen on M5 / macOS 27) moves the capacity figures into the nested
        // "BatteryData" dictionary and drops some top-level keys, so we check both places.
        let batteryData = properties["BatteryData"] as? [String: Any] ?? [:]

        var reading = Reading()
        reading.cycleCount = int(properties["CycleCount"]) ?? int(batteryData["CycleCount"])
        reading.designCapacity = int(properties["DesignCapacity"]) ?? int(batteryData["DesignCapacity"])

        // On Apple Silicon "MaxCapacity" is a percentage and the mAh value lives in
        // "AppleRawMaxCapacity" (or BatteryData.NominalChargeCapacity, the same raw figure).
        // Older Intel firmware only has "MaxCapacity" in mAh.
        if let raw = int(properties["AppleRawMaxCapacity"])
            ?? int(batteryData["NominalChargeCapacity"])
            ?? int(batteryData["FullChargeCapacity"]) {
            reading.rawMaxCapacity = raw
        } else if let max = int(properties["MaxCapacity"]), max > 200 {
            reading.rawMaxCapacity = max
        }

        // Temperature is reported in hundredths of a degree Celsius (e.g. 3055 = 30.55 °C).
        // When the registry doesn't publish it, fall back to the SMC battery thermistor.
        if let temperature = int(properties["Temperature"]) ?? int(batteryData["Temperature"]) {
            reading.temperature = Double(temperature) / 100
        } else {
            reading.temperature = SMC.batteryTemperature()
        }

        reading.voltage = int(properties["Voltage"])
        // Amperage is a signed value that IOKit sometimes surfaces as an unsigned 64-bit
        // number; `int(_:)` reinterprets it so discharging currents come back negative.
        reading.amperage = int(properties["InstantAmperage"]) ?? int(properties["Amperage"])

        reading.isCharging = properties["IsCharging"] as? Bool
        reading.externalConnected = properties["ExternalConnected"] as? Bool
        reading.fullyCharged = properties["FullyCharged"] as? Bool

        if let adapter = properties["AdapterDetails"] as? [String: Any] {
            reading.adapterWatts = int(adapter["Watts"])
        }
        return reading
    }

    /// Fetches every property of the AppleSmartBattery service as a Swift dictionary.
    private static func registryProperties() -> [String: Any]? {
        // IOServiceMatching builds a matching dictionary for IOService objects whose class
        // (or superclass) is "AppleSmartBattery". IOServiceGetMatchingService consumes that
        // dictionary and returns the first match, or IO_OBJECT_NULL on desktops.
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        // Every io_object_t we receive must be balanced with IOObjectRelease.
        defer { IOObjectRelease(service) }

        // IORegistryEntryCreateCFProperties snapshots all of the entry's properties into a
        // new CFMutableDictionary that we own.
        var unmanaged: Unmanaged<CFMutableDictionary>?
        let result = IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0)
        guard result == KERN_SUCCESS, let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return dictionary
    }

    /// Converts an IORegistry number to `Int`, reinterpreting 64-bit unsigned values as signed.
    private static func int(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        return Int(truncatingIfNeeded: number.int64Value)
    }
}
