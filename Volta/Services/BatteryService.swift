//
//  BatteryService.swift
//  Volta
//

import Foundation
import IOKit.ps
import Observation

/// The single source of truth for battery state. Views only read from this.
///
/// Updates are event-driven: IOKit calls us whenever the power source changes
/// (percentage tick, plug/unplug, charge state). The only timer is a 60-second
/// refresh of temperature/health telemetry that runs only while the popover is open.
@Observable
final class BatteryService {
    private(set) var info = BatteryInfo()
    private(set) var lastUpdated = Date()

    @ObservationIgnored private var runLoopSource: CFRunLoopSource?
    @ObservationIgnored private var detailTimer: Timer?
    @ObservationIgnored private var listeners: [(_ new: BatteryInfo, _ old: BatteryInfo) -> Void] = []

    init() {
        refresh()
    }

    /// Starts listening for IOKit power-source notifications.
    func start() {
        guard runLoopSource == nil else { return }

        // IOPSNotificationCreateRunLoopSource creates a CFRunLoopSource that invokes our C
        // callback whenever any power source changes. The context pointer is handed back to
        // the callback so it can find this service. We own the returned source.
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(powerSourceDidChange, context)?
            .takeRetainedValue() else { return }

        // Adding the source to the main run loop means callbacks arrive on the main thread.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = source
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
        setDetailPolling(false)
    }

    /// Registers a callback that runs after every change to `info`.
    func addListener(_ listener: @escaping (_ new: BatteryInfo, _ old: BatteryInfo) -> Void) {
        listeners.append(listener)
    }

    /// Enables the 60-second telemetry refresh. Call with `true` when the popover opens.
    func setDetailPolling(_ active: Bool) {
        detailTimer?.invalidate()
        detailTimer = nil
        guard active else { return }
        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        detailTimer = timer
    }

    /// Re-reads both IOPowerSources and the AppleSmartBattery registry entry.
    func refresh() {
        let old = info
        var new = BatteryInfo()

        let power = PowerSourceReader.read()
        new.hasBattery = power.hasBattery
        new.percentage = power.percentage
        new.isCharging = power.isCharging
        new.isOnAC = power.isOnAC
        new.isFullyCharged = power.isCharged
        new.timeToEmpty = power.timeToEmpty
        new.timeToFull = power.timeToFull
        new.adapterWatts = power.isOnAC ? PowerSourceReader.adapterWatts() : nil

        if power.hasBattery, let smart = SmartBatteryReader.read() {
            new.cycleCount = smart.cycleCount
            new.rawMaxCapacity = smart.rawMaxCapacity
            new.designCapacity = smart.designCapacity
            new.temperature = smart.temperature
            new.voltage = smart.voltage
            new.amperage = smart.amperage
            new.isFullyCharged = new.isFullyCharged || (smart.fullyCharged ?? false)
            if new.adapterWatts == nil, power.isOnAC { new.adapterWatts = smart.adapterWatts }
        }

        lastUpdated = Date()
        guard new != old else { return }
        info = new
        for listener in listeners { listener(new, old) }
    }
}

/// C callback for IOPSNotificationCreateRunLoopSource. It must be a plain function
/// (no captures), so it recovers the service from the context pointer.
nonisolated private func powerSourceDidChange(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let service = Unmanaged<BatteryService>.fromOpaque(context).takeUnretainedValue()
    // The run loop source is attached to the main run loop, so we're already on main.
    MainActor.assumeIsolated { service.refresh() }
}
