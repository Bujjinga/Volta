//
//  AppModel.swift
//  Volta
//

import Foundation
import Observation

/// Owns every long-lived service and wires them together.
@Observable
final class AppModel {
    /// Shared so the app delegate can reach services during termination.
    static let shared = AppModel()

    let battery: BatteryService
    let alertRules: AlertRuleStore
    let charge: ChargeController
    let energy = EnergyService()
    let devices = DeviceService()
    @ObservationIgnored let alerts: AlertEngine
    /// Devices already alerted for; cleared once they charge back above the threshold.
    @ObservationIgnored private var alertedDevices: Set<ConnectedDevice.ID> = []
    @ObservationIgnored let history: HistoryService
    @ObservationIgnored let iconRenderer = MenuBarIconRenderer()

    private init() {
        SettingsDefaults.register()
        battery = BatteryService()
        alertRules = AlertRuleStore()
        alerts = AlertEngine(store: alertRules)
        history = HistoryService()
        charge = ChargeController()

        battery.addListener { [alerts, history, charge] new, _ in
            alerts.evaluate(new)
            history.record(new)
            charge.evaluate(new)
        }
        battery.start()

        // Evaluate once at launch so a Mac that starts below a threshold still alerts.
        let info = battery.info
        alerts.evaluate(info)
        history.start(with: info)
        charge.evaluate(info)

        devices.onUpdate = { [weak self] devices in self?.evaluateDeviceAlerts(devices) }
        devices.start()
    }

    /// Low-battery alerts for peripherals, once per crossing (same rule as the Mac's alerts).
    private func evaluateDeviceAlerts(_ devices: [ConnectedDevice]) {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: SettingsKey.deviceAlertsEnabled) else { return }
        let threshold = defaults.integer(forKey: SettingsKey.deviceAlertThreshold)

        for device in devices {
            if device.percentage > threshold + 5 {
                alertedDevices.remove(device.id)
            } else if device.percentage <= threshold, !alertedDevices.contains(device.id) {
                alertedDevices.insert(device.id)
                alerts.presentAdHoc(
                    title: "\(device.displayName) at \(device.percentage)%",
                    message: "Charge it soon so it doesn't die mid-task.",
                    symbol: device.kind.symbol,
                    level: device.percentage
                )
            }
        }
    }
}
