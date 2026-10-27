//
//  OverviewView.swift
//  Volta
//

import SwiftUI

/// The "Overview" tab: the charge-limit toggle (when available) and connected devices.
struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.chargeLimitEnabled) private var limitEnabled = false
    @AppStorage(SettingsKey.chargeLimit) private var limit = SettingsDefaults.chargeLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.charge.method.isSupported && model.charge.isHelperReady {
                HStack {
                    Label("Limit charge to \(limit)%", systemImage: "bolt.batteryblock.fill")
                    Spacer()
                    Toggle("Limit charge", isOn: $limitEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .onChange(of: limitEnabled) { model.charge.settingsChanged() }
            }
            DeviceListView(devices: model.devices.devices)
        }
        .onAppear { model.devices.refresh() }
    }
}

struct DeviceListView: View {
    let devices: [ConnectedDevice]

    @AppStorage(SettingsKey.showMice) private var showMice = true
    @AppStorage(SettingsKey.showKeyboards) private var showKeyboards = true
    @AppStorage(SettingsKey.showAudio) private var showAudio = true
    @AppStorage(SettingsKey.showOtherDevices) private var showOther = true

    private var visible: [ConnectedDevice] {
        devices.filter { device in
            switch device.kind {
            case .mouse, .trackpad: showMice
            case .keyboard: showKeyboards
            case .audio: showAudio
            case .other: showOther
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Devices")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if visible.isEmpty {
                Text("No connected devices with a battery.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visible) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.kind.symbol)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text(device.displayName)
                            .lineLimit(1)
                        Spacer()
                        DeviceBatteryBar(percentage: device.percentage)
                            .frame(width: 44, height: 6)
                        Text("\(device.percentage)%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

struct DeviceBatteryBar: View {
    let percentage: Int
    private var palette = PaletteSettings()

    init(percentage: Int) {
        self.percentage = percentage
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(palette.palette.color(for: percentage))
                    .frame(width: max(3, proxy.size.width * CGFloat(percentage) / 100))
            }
        }
    }
}
