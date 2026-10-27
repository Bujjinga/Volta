//
//  PopoverView.swift
//  Volta
//

import AppKit
import SwiftData
import SwiftUI

/// The MenuBarExtra window content (~340 pt wide).
struct PopoverView: View {
    @Environment(BatteryService.self) private var battery
    @Environment(\.openSettings) private var openSettings

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case health = "Health"
        case energy = "Energy"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .overview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            BatteryHeaderView(info: battery.info)
            QuickStatsView(info: battery.info)

            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch tab {
            case .overview:
                OverviewView()
            case .health:
                HealthView()
            case .energy:
                EnergyView()
            }

            Divider()
            footer
        }
        .padding(14)
        .frame(width: 340)
        // Telemetry polling only runs while this window is visible.
        .onAppear { battery.setDetailPolling(true) }
        .onDisappear { battery.setDetailPolling(false) }
    }

    private var footer: some View {
        HStack {
            Button {
                // Menu bar apps aren't active by default; activate so Settings comes forward.
                NSApplication.shared.activate()
                openSettings()
            } label: {
                Label("Settings…", systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            Spacer()
            Button("Quit Volta") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

#Preview {
    PopoverView()
        .environment(AppModel.shared)
        .environment(AppModel.shared.battery)
        .modelContainer(AppModel.shared.history.container)
}

/// Big percentage, status line, and charger wattage.
struct BatteryHeaderView: View {
    let info: BatteryInfo
    private var palette = PaletteSettings()
    private var iconStyle = IconStyleSettings()

    init(info: BatteryInfo) {
        self.info = info
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if info.hasBattery {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(info.percentage)%")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(info.percentage)))
                    Text(info.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if let watts = info.adapterWatts {
                        Label("\(watts) W charger", systemImage: "powerplug.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                BatteryIconView(
                    percentage: info.percentage,
                    isCharging: info.isCharging,
                    tint: palette.palette.color(for: info.percentage, isCharging: info.isCharging),
                    // Mirror the menu bar shape, but keep the number inside at this size.
                    style: BatteryIconStyle(shape: iconStyle.style.shape, percent: .inside, showBolt: iconStyle.style.showBolt),
                    height: 24
                )
            } else {
                Label("No internal battery", systemImage: "powerplug.fill")
                    .font(.title3.weight(.semibold))
                Spacer()
            }
        }
        .animation(.snappy, value: info.percentage)
    }
}

/// Health, cycles, temperature, and power draw.
struct QuickStatsView: View {
    let info: BatteryInfo

    var body: some View {
        if info.hasBattery {
            HStack(spacing: 8) {
                StatTile(title: "Health", value: info.healthPercent.map { String(format: "%.0f%%", $0) } ?? "–", symbol: "heart.fill")
                    .help("Raw value: AppleRawMaxCapacity ÷ DesignCapacity. macOS smooths its own figure over time, so System Settings may show a slightly different number.")
                StatTile(title: "Cycles", value: info.cycleCount.map(String.init) ?? "–", symbol: "arrow.triangle.2.circlepath")
                StatTile(title: "Temp", value: info.temperature.map { String(format: "%.1f°", $0) } ?? "–", symbol: "thermometer.medium", isWarning: (info.temperature ?? 0) > 40)
                StatTile(title: "Power", value: info.powerWatts.map { String(format: "%.1f W", abs($0)) } ?? "–", symbol: "bolt.fill")
                    .help((info.powerWatts ?? 0) < 0 ? "Power leaving the battery" : "Power flowing into the battery")
            }
        }
    }
}

struct StatTile: View {
    let title: String
    let value: String
    let symbol: String
    var isWarning = false

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : symbol)
                .font(.caption)
                .foregroundStyle(isWarning ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
            Text(value)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
    }
}
