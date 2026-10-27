//
//  BatteryInfo.swift
//  Volta
//

import Foundation

/// A snapshot of everything Volta knows about the internal battery at one moment.
///
/// Values that come from the IORegistry are optional because not every Mac
/// (or every macOS release) exposes every key.
struct BatteryInfo: Equatable, Sendable {
    /// `false` on desktops (Mac mini, Mac Studio, iMac, Mac Pro).
    var hasBattery = false

    // MARK: From IOPowerSources (IOPSCopyPowerSourcesInfo)
    var percentage = 0
    var isCharging = false
    var isOnAC = false
    var isFullyCharged = false
    /// Minutes until empty. `nil` while macOS is still estimating.
    var timeToEmpty: Int?
    /// Minutes until full. `nil` while macOS is still estimating.
    var timeToFull: Int?

    // MARK: From the AppleSmartBattery IORegistry entry
    var cycleCount: Int?
    /// Current full-charge capacity in mAh (AppleRawMaxCapacity).
    var rawMaxCapacity: Int?
    /// Factory capacity in mAh (DesignCapacity).
    var designCapacity: Int?
    /// Degrees Celsius.
    var temperature: Double?
    /// Millivolts.
    var voltage: Int?
    /// Milliamps. Negative while discharging, positive while charging.
    var amperage: Int?
    /// Connected charger's rated wattage.
    var adapterWatts: Int?

    /// Raw health: AppleRawMaxCapacity ÷ DesignCapacity × 100.
    ///
    /// macOS's own "Maximum Capacity" figure in System Settings is smoothed over time
    /// and rounded, so it can differ from this raw number by a few percent.
    var healthPercent: Double? {
        guard let rawMaxCapacity, let designCapacity, designCapacity > 0 else { return nil }
        return Double(rawMaxCapacity) / Double(designCapacity) * 100
    }

    /// Instantaneous power in watts: V (mV) × I (mA) ÷ 1,000,000.
    /// Negative while discharging (power leaving the battery).
    var powerWatts: Double? {
        guard let voltage, let amperage else { return nil }
        return Double(voltage) * Double(amperage) / 1_000_000
    }

    /// A short, human-readable status line for the popover header.
    var statusText: String {
        guard hasBattery else { return "No internal battery" }
        if isFullyCharged || (isOnAC && percentage >= 100) { return "Fully charged" }
        if isCharging {
            if let timeToFull, timeToFull > 0 { return "Charging – \(Self.format(minutes: timeToFull)) to full" }
            return "Charging – estimating…"
        }
        if isOnAC { return "On power adapter – not charging" }
        if let timeToEmpty, timeToEmpty > 0 { return "On battery – \(Self.format(minutes: timeToEmpty)) left" }
        return "On battery – estimating…"
    }

    static func format(minutes: Int) -> String {
        String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}
