//
//  PowerSourceReader.swift
//  Volta
//

import Foundation
import IOKit.ps

/// Reads the high-level power source state from the IOPowerSources API (IOKit/ps).
///
/// This is the same data that drives the system battery menu, and it's cheap to read.
enum PowerSourceReader {
    struct Reading {
        var hasBattery = false
        var percentage = 0
        var isCharging = false
        var isOnAC = false
        var isCharged = false
        var timeToEmpty: Int?
        var timeToFull: Int?
    }

    static func read() -> Reading {
        var reading = Reading()

        // IOPSCopyPowerSourcesInfo returns an opaque CFTypeRef "blob" describing every
        // power source attached to the system. It's only meaningful when passed back into
        // the other IOPS* functions below. We own the returned reference (Copy rule).
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return reading }

        // IOPSGetProvidingPowerSourceType tells us what is currently powering the Mac:
        // "AC Power", "Battery Power", or "UPS Power". It follows the Get rule (not owned).
        if let providing = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() as String? {
            reading.isOnAC = providing == kIOPSACPowerValue
        }

        // IOPSCopyPowerSourcesList returns a CFArray of opaque handles, one per power
        // source (internal battery, UPS, …). We own the array.
        guard let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else {
            return reading
        }

        for source in sources {
            // IOPSGetPowerSourceDescription returns a CFDictionary of kIOPS* keys for one
            // source. Get rule: the dictionary is owned by `blob`, so we don't release it.
            guard let description = IOPSGetPowerSourceDescription(blob, source)?
                .takeUnretainedValue() as? [String: Any] else { continue }

            // Only the internal battery matters here; skip UPS units and accessories.
            guard description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }

            reading.hasBattery = description[kIOPSIsPresentKey] as? Bool ?? true

            // Current/Max capacity are already normalized to a 0–100 scale by IOPS.
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = description[kIOPSMaxCapacityKey] as? Int ?? 100
            reading.percentage = maximum > 0
                ? Int((Double(current) / Double(maximum) * 100).rounded())
                : current

            reading.isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            reading.isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
            if let state = description[kIOPSPowerSourceStateKey] as? String {
                reading.isOnAC = state == kIOPSACPowerValue
            }

            // Both time keys are minutes; -1 means "still calculating".
            if let minutes = description[kIOPSTimeToEmptyKey] as? Int, minutes > 0 {
                reading.timeToEmpty = minutes
            }
            if let minutes = description[kIOPSTimeToFullChargeKey] as? Int, minutes > 0 {
                reading.timeToFull = minutes
            }
            break
        }
        return reading
    }

    /// Wattage of the connected charger, if any.
    static func adapterWatts() -> Int? {
        // IOPSCopyExternalPowerAdapterDetails returns a dictionary describing the attached
        // power adapter (Watts, Current, Voltage, Name…), or NULL when nothing is plugged in.
        guard let details = IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any] else {
            return nil
        }
        return (details[kIOPSPowerAdapterWattsKey] as? NSNumber)?.intValue
    }
}
