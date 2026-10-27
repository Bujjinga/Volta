//
//  DevicesSettingsView.swift
//  Volta
//

import SwiftUI

struct DevicesSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.showMice) private var showMice = true
    @AppStorage(SettingsKey.showKeyboards) private var showKeyboards = true
    @AppStorage(SettingsKey.showAudio) private var showAudio = true
    @AppStorage(SettingsKey.showOtherDevices) private var showOther = true
    @AppStorage(SettingsKey.deviceAlertsEnabled) private var alertsEnabled = false
    @AppStorage(SettingsKey.deviceAlertThreshold) private var threshold = SettingsDefaults.deviceAlertThreshold

    var body: some View {
        Form {
            Section("Show in the popover") {
                Toggle("Mice & trackpads", isOn: $showMice)
                Toggle("Keyboards", isOn: $showKeyboards)
                Toggle("AirPods & headphones", isOn: $showAudio)
                Toggle("Other Bluetooth devices", isOn: $showOther)
            }

            Section {
                Toggle("Alert when a device's battery is low", isOn: $alertsEnabled)
                Stepper("Alert at \(threshold)%", value: $threshold, in: 5...50, step: 5)
                    .disabled(!alertsEnabled)
            } header: {
                Text("Low battery alerts")
            } footer: {
                Text("Uses the same banner as Mac alerts. Bluetooth levels refresh every 5 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Currently connected") {
                if model.devices.devices.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                } else {
                    ForEach(model.devices.devices) { device in
                        LabeledContent(device.displayName, value: "\(device.percentage)%")
                    }
                }
                Button("Refresh Now") { model.devices.refresh(forceBluetooth: true) }
                Text("iPhone and iPad battery levels aren't available through any public macOS API, so Volta doesn't show them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
