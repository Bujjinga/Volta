//
//  ChargingSettingsView.swift
//  Volta
//

import ServiceManagement
import SwiftUI

struct ChargingSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.chargeLimitEnabled) private var limitEnabled = false
    @AppStorage(SettingsKey.chargeLimit) private var limit = SettingsDefaults.chargeLimit
    @AppStorage(SettingsKey.sailingMode) private var sailing = false

    var body: some View {
        let charge = model.charge
        Form {
            Section {
                Label {
                    Text("Charge limiting writes to the System Management Controller through a privileged helper. Apple doesn't document these keys, so this feature may stop working after a macOS or firmware update. Volta always restores normal charging when it quits, crashes, or the helper is removed.")
                        .font(.callout)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }

            Section("This Mac") {
                LabeledContent("Control method", value: charge.method.title)
                LabeledContent("Helper") {
                    Text(statusText(charge.helperStatus))
                        .foregroundStyle(charge.isHelperReady ? .green : .secondary)
                }
                if !charge.isHelperBundled {
                    Text("The helper's LaunchDaemon plist isn't embedded in this build. See README › \"Embedding the helper\".")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                HStack {
                    if charge.isHelperReady {
                        Button("Remove Helper…", role: .destructive) { charge.uninstallHelper() }
                    } else {
                        Button("Install Helper…") { charge.installHelper() }
                            .disabled(!charge.method.isSupported || !charge.isHelperBundled)
                    }
                    if charge.helperStatus == .requiresApproval {
                        Button("Open Login Items Settings") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let error = charge.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }

            Section("Limit") {
                Toggle("Limit charging", isOn: $limitEnabled)
                HStack {
                    Slider(value: limitBinding, in: 50...100, step: 5) {
                        Text("Stop at")
                    }
                    Text("\(limit)%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .disabled(!limitEnabled)
                Toggle("Pause charging while on AC (sailing mode)", isOn: $sailing)
                    .help("Holds the battery at its current level while plugged in.")
                Button(charge.isTopUpActive ? "Charging to 100%…" : "Charge to 100% Once") {
                    charge.chargeToFullOnce()
                }
                .disabled(charge.isTopUpActive || !(limitEnabled || sailing))
            }
            .disabled(!charge.method.isSupported || !charge.isHelperReady)
        }
        .formStyle(.grouped)
        .onAppear { charge.refreshStatus() }
        .onChange(of: limitEnabled) { charge.settingsChanged() }
        .onChange(of: limit) { charge.settingsChanged() }
        .onChange(of: sailing) { charge.settingsChanged() }
    }

    private var limitBinding: Binding<Double> {
        Binding(get: { Double(limit) }, set: { limit = Int($0) })
    }

    private func statusText(_ status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "Installed and running"
        case .requiresApproval: "Waiting for approval in System Settings"
        case .notRegistered: "Not installed"
        case .notFound: "Not installed"
        @unknown default: "Unknown"
        }
    }
}
