//
//  DeviceService.swift
//  Volta
//

import Foundation
import IOKit
import Observation

/// Collects battery levels for connected peripherals.
///
/// - Apple HID accessories (Magic Mouse, Keyboard, Trackpad) publish "BatteryPercent"
///   on their `AppleDeviceManagementHIDEventService` IORegistry entry – cheap to read.
/// - Other Bluetooth devices (AirPods, Beats, third-party) are only exposed through
///   `system_profiler SPBluetoothDataType -json`, which is slow, so it runs at most
///   every 5 minutes.
/// - iPhone / iPad: no reliable public API, so they're intentionally not shown.
@Observable
final class DeviceService {
    private(set) var devices: [ConnectedDevice] = []

    @ObservationIgnored var onUpdate: (([ConnectedDevice]) -> Void)?
    @ObservationIgnored private var bluetoothDevices: [ConnectedDevice] = []
    @ObservationIgnored private var lastBluetoothRefresh: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var isRefreshingBluetooth = false

    private static let bluetoothInterval: TimeInterval = 5 * 60

    func start() {
        refresh()
        let timer = Timer(timeInterval: Self.bluetoothInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(forceBluetooth: true) }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// HID devices are re-read every time; Bluetooth only when stale (or forced).
    func refresh(forceBluetooth: Bool = false) {
        let hid = Self.readHIDDevices()
        publish(hid: hid)

        let stale = lastBluetoothRefresh.map { Date.now.timeIntervalSince($0) > Self.bluetoothInterval } ?? true
        guard (forceBluetooth || stale), !isRefreshingBluetooth else { return }
        isRefreshingBluetooth = true
        Task { [weak self] in
            let bluetooth = await Task.detached(priority: .utility) {
                Self.parseBluetooth(Self.runSystemProfiler())
            }.value
            guard let self else { return }
            self.bluetoothDevices = bluetooth
            self.lastBluetoothRefresh = .now
            self.isRefreshingBluetooth = false
            self.publish(hid: Self.readHIDDevices())
        }
    }

    private func publish(hid: [ConnectedDevice]) {
        // HID readings are fresher, so they win when both sources report the same device.
        let hidNames = Set(hid.map(\.name))
        let merged = hid + bluetoothDevices.filter { !hidNames.contains($0.name) }
        let sorted = merged.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        guard sorted != devices else { return }
        devices = sorted
        onUpdate?(sorted)
    }

    // MARK: - IORegistry (HID)

    nonisolated static func readHIDDevices() -> [ConnectedDevice] {
        // IOServiceGetMatchingServices returns an iterator over every registry entry whose
        // class is AppleDeviceManagementHIDEventService (one per Apple accessory).
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleDeviceManagementHIDEventService"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var result: [ConnectedDevice] = []
        // IOIteratorNext hands out each entry (retained) until it returns 0.
        var service = IOIteratorNext(iterator)
        while service != IO_OBJECT_NULL {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            // IORegistryEntryCreateCFProperty copies a single property. Built-in keyboards
            // and trackpads don't have BatteryPercent, which conveniently filters them out.
            guard let percent = property(service, "BatteryPercent") as? Int else { continue }
            let name = property(service, "Product") as? String ?? "Accessory"
            result.append(ConnectedDevice(name: name, part: nil, kind: .guess(from: name), percentage: percent))
        }
        return result
    }

    nonisolated private static func property(_ service: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    // MARK: - system_profiler (Bluetooth)

    nonisolated private static func runSystemProfiler() -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return Data() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    /// Reads `device_connected` entries and their `device_batteryLevel*` fields ("80%").
    nonisolated static func parseBluetooth(_ data: Data) -> [ConnectedDevice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]] else { return [] }

        let parts: [(key: String, label: String?)] = [
            ("device_batteryLevelMain", nil),
            ("device_batteryLevel", nil),
            ("device_batteryLevelLeft", "Left"),
            ("device_batteryLevelRight", "Right"),
            ("device_batteryLevelCase", "Case"),
        ]

        var result: [ConnectedDevice] = []
        for section in sections {
            for entry in section["device_connected"] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let properties = value as? [String: Any] else { continue }
                    let kind = ConnectedDevice.Kind.guess(from: "\(name) \(properties["device_minorType"] as? String ?? "")")
                    for part in parts {
                        guard let text = properties[part.key] as? String,
                              let percent = Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))) else { continue }
                        result.append(ConnectedDevice(name: name, part: part.label, kind: kind, percentage: percent))
                    }
                }
            }
        }
        return result
    }
}
