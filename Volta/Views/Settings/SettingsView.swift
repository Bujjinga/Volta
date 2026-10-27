//
//  SettingsView.swift
//  Volta
//

import AppKit
import SwiftUI

/// The Settings scene (⌘,).
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
            Tab("Icon", systemImage: "battery.75percent") {
                IconSettingsView()
            }
            Tab("Effects", systemImage: "sparkles") {
                EffectsSettingsView()
            }
            Tab("Alerts", systemImage: "bell.badge") {
                AlertsSettingsView()
            }
            Tab("Charging", systemImage: "bolt.batteryblock") {
                ChargingSettingsView()
            }
            Tab("Devices", systemImage: "airpods") {
                DevicesSettingsView()
            }
            Tab("About", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .frame(width: 600, height: 560)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Launch Volta at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            try LaunchAtLogin.set(enabled)
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
            }

            Section {
                LabeledContent("macOS battery icon") {
                    Button("Open Control Center Settings…") {
                        // Battery › "Show in Menu Bar" lives in Control Center settings.
                        if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Menu bar")
            } footer: {
                Text("Seeing two battery icons? Turn off Battery › “Show in Menu Bar” in Control Center settings so only Volta's icon remains.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Icon

struct IconSettingsView: View {
    @AppStorage(SettingsKey.iconTheme) private var theme = IconTheme.colored
    @AppStorage(SettingsKey.iconShape) private var shape = IconShape.rounded
    @AppStorage(SettingsKey.iconPercent) private var percent = IconPercentPlacement.inside
    @AppStorage(SettingsKey.iconSize) private var size = IconSize.regular
    @AppStorage(SettingsKey.iconShowBolt) private var showBolt = true
    @AppStorage(SettingsKey.greenAbove) private var greenAbove = SettingsDefaults.greenAbove
    @AppStorage(SettingsKey.redAtOrBelow) private var redAtOrBelow = SettingsDefaults.redAtOrBelow
    @AppStorage(SettingsKey.colorHigh) private var colorHigh = SettingsDefaults.colorHigh
    @AppStorage(SettingsKey.colorMedium) private var colorMedium = SettingsDefaults.colorMedium
    @AppStorage(SettingsKey.colorLow) private var colorLow = SettingsDefaults.colorLow
    @AppStorage(SettingsKey.colorCharging) private var colorCharging = SettingsDefaults.colorCharging
    @AppStorage(SettingsKey.useChargingColor) private var useChargingColor = false
    private var palette = PaletteSettings()

    var body: some View {
        Form {
            Section {
                iconPreview
            }

            Section("Style") {
                Picker("Color", selection: $theme) {
                    ForEach(IconTheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("Shape", selection: $shape) {
                    ForEach(IconShape.allCases) { Text($0.title).tag($0) }
                }
                .disabled(theme == .textOnly)
                Picker("Percentage", selection: $percent) {
                    ForEach(IconPercentPlacement.allCases) { Text($0.title).tag($0) }
                }
                .disabled(theme == .textOnly)
                Picker("Size", selection: $size) {
                    ForEach(IconSize.allCases) { Text($0.title).tag($0) }
                }
                .disabled(theme == .textOnly)
                Toggle("Show charging bolt", isOn: $showBolt)
            }

            Section {
                ColorPicker("High", selection: $colorHigh.color, supportsOpacity: false)
                ColorPicker("Medium", selection: $colorMedium.color, supportsOpacity: false)
                ColorPicker("Low", selection: $colorLow.color, supportsOpacity: false)
                Toggle("Use a separate color while charging", isOn: $useChargingColor)
                if useChargingColor {
                    ColorPicker("Charging", selection: $colorCharging.color, supportsOpacity: false)
                }
                Stepper("High above \(greenAbove)%", value: $greenAbove, in: (redAtOrBelow + 1)...95, step: 5)
                Stepper("Low at or below \(redAtOrBelow)%", value: $redAtOrBelow, in: 5...(greenAbove - 1), step: 1)
            } header: {
                Text("Colors")
            } footer: {
                Text("Colors apply to the Colored style, the popover, and device bars. Between the two thresholds the medium color is used.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(theme == .monochrome)

            Section {
                Button("Restore Default Look") {
                    SettingsDefaults.resetAppearance()
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Live preview at real menu bar size on light and dark bars.
    private var iconPreview: some View {
        let style = BatteryIconStyle(shape: shape, percent: percent, size: size, showBolt: showBolt)
        let samples: [(Int, Bool)] = [(86, false), (42, true), (12, false)]
        return HStack(spacing: 12) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                HStack(spacing: 14) {
                    ForEach(samples, id: \.0) { level, charging in
                        if theme == .textOnly {
                            Text(charging && showBolt ? "⚡︎\(level)%" : "\(level)%")
                                .font(.system(size: 13).monospacedDigit())
                        } else {
                            BatteryIconView(
                                percentage: level,
                                isCharging: charging,
                                tint: theme == .colored ? palette.palette.color(for: level, isCharging: charging) : .primary,
                                style: style
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 28)
                .background(scheme == .light ? Color.white.opacity(0.85) : Color.black.opacity(0.75), in: .rect(cornerRadius: 6))
                .environment(\.colorScheme, scheme)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Effects

struct EffectsSettingsView: View {
    @Environment(AppModel.self) private var model

    @AppStorage(SettingsKey.glowLowColor) private var glowLow = SettingsDefaults.glowLowColor
    @AppStorage(SettingsKey.glowFullColor) private var glowFull = SettingsDefaults.glowFullColor
    @AppStorage(SettingsKey.glowIntensity) private var intensity = SettingsDefaults.glowIntensity
    @AppStorage(SettingsKey.glowWidth) private var width = SettingsDefaults.glowWidth
    @AppStorage(SettingsKey.glowPulses) private var pulses = SettingsDefaults.glowPulses
    @AppStorage(SettingsKey.glowSpeed) private var speed = SettingsDefaults.glowSpeed

    @AppStorage(SettingsKey.bannerPosition) private var bannerPosition = BannerPosition.topCenter
    @AppStorage(SettingsKey.bannerDuration) private var bannerDuration = SettingsDefaults.bannerDuration

    @AppStorage(SettingsKey.soundsMuted) private var muted = false
    @AppStorage(SettingsKey.masterVolume) private var masterVolume = SettingsDefaults.masterVolume

    var body: some View {
        Form {
            Section {
                ColorPicker("Low battery color", selection: $glowLow.color, supportsOpacity: false)
                ColorPicker("Charged / unplug color", selection: $glowFull.color, supportsOpacity: false)
                slider("Brightness", value: $intensity, in: 0.2...1, format: { "\(Int($0 * 100))%" })
                slider("Thickness", value: $width, in: 0.5...2, format: { String(format: "%.1f×", $0) })
                slider("Speed", value: $speed, in: 0.5...2, format: { String(format: "%.1f×", $0) })
                Stepper("Pulses: \(pulses)", value: $pulses, in: 1...6)
                HStack {
                    Spacer()
                    Button("Preview Low Glow") { model.alerts.previewGlow(.low) }
                    Button("Preview Charged Glow") { model.alerts.previewGlow(.full) }
                }
            } header: {
                Text("Screen glow")
            }

            Section("Banner") {
                Picker("Position", selection: $bannerPosition) {
                    ForEach(BannerPosition.allCases) { Text($0.title).tag($0) }
                }
                Picker("Stay on screen", selection: $bannerDuration) {
                    Text("5 seconds").tag(5.0)
                    Text("12 seconds").tag(12.0)
                    Text("30 seconds").tag(30.0)
                    Text("Until dismissed").tag(0.0)
                }
                HStack {
                    Spacer()
                    Button("Preview Banner") { model.alerts.previewBanner() }
                }
            }

            Section {
                Toggle("Mute all alert sounds", isOn: $muted)
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: $masterVolume, in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                .disabled(muted)
                HStack {
                    Spacer()
                    Button("Play Sample") { SoundPlayer.play(.system("Glass"), volume: 1) }
                        .disabled(muted)
                }
            } header: {
                Text("Sound")
            } footer: {
                Text("Each alert has its own sound and volume (Alerts tab). The master volume scales all of them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func slider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, format: @escaping (Double) -> String) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text(format(value.wrappedValue))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
    }
}

// MARK: - About

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.batteryblock.fill")
                .font(.system(size: 54))
                .foregroundStyle(.green.gradient)
            Text("Volta")
                .font(.largeTitle.weight(.semibold))
            Text(version)
                .foregroundStyle(.secondary)
            Text("A native battery companion for your Mac.")
                .font(.callout)
                .foregroundStyle(.secondary)
            // Sparkle can be wired in here; see README › "Updates".
            Button("Check for Updates…") {}
                .disabled(true)
                .help("Integrate Sparkle to enable update checks.")
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Icon settings") {
    IconSettingsView()
        .frame(width: 600, height: 560)
}

#Preview("Effects settings") {
    EffectsSettingsView()
        .environment(AppModel.shared)
        .frame(width: 600, height: 560)
}
