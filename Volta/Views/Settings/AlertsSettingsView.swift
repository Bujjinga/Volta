//
//  AlertsSettingsView.swift
//  Volta
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AlertsSettingsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.respectFocus) private var respectFocus = true
    @AppStorage(SettingsKey.systemNotifications) private var systemNotifications = false

    @State private var selection: Set<AlertRule.ID> = []
    @State private var editing: AlertRule?

    var body: some View {
        @Bindable var store = model.alertRules

        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selection) {
                ForEach($store.rules) { $rule in
                    AlertRuleRow(rule: $rule) {
                        model.alerts.test(rule)
                    } onEdit: {
                        editing = rule
                    }
                    .tag(rule.id)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .contextMenu(forSelectionType: AlertRule.ID.self) { ids in
                Button("Delete", role: .destructive) { store.delete(ids) }
            } primaryAction: { ids in
                if let id = ids.first { editing = store.rules.first { $0.id == id } }
            }

            HStack {
                Button {
                    editing = AlertRule(trigger: .dropsTo, threshold: 15)
                } label: {
                    Image(systemName: "plus")
                }
                Button {
                    store.delete(selection)
                    selection.removeAll()
                } label: {
                    Image(systemName: "minus")
                }
                .disabled(selection.isEmpty)
                Spacer()
                Button("Restore Defaults") { store.resetToDefaults() }
            }

            Toggle("Stay quiet during Focus / Do Not Disturb (banner only, no sound or glow)", isOn: $respectFocus)
                .onChange(of: respectFocus) { _, on in if on { FocusMonitor.requestAuthorization() } }
            Toggle("Also send a standard macOS notification", isOn: $systemNotifications)
                .onChange(of: systemNotifications) { _, on in
                    guard on else { return }
                    Task {
                        if await !NotificationSender.requestAuthorization() { systemNotifications = false }
                    }
                }
        }
        .padding(20)
        .sheet(item: $editing) { rule in
            AlertRuleEditor(rule: rule) { saved in
                if store.rules.contains(where: { $0.id == saved.id }) {
                    store.update(saved)
                } else {
                    store.add(saved)
                }
            }
        }
    }
}

struct AlertRuleRow: View {
    @Binding var rule: AlertRule
    let onTest: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: $rule.isEnabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.mini)
            Image(systemName: rule.trigger == .dropsTo ? "battery.25percent" : "battery.100percent.bolt")
                .foregroundStyle(rule.trigger == .dropsTo ? .red : .green)
            VStack(alignment: .leading, spacing: 1) {
                Text(rule.summary).font(.body.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Test", action: onTest)
                .controlSize(.small)
            Button("Edit", action: onEdit)
                .controlSize(.small)
        }
        .opacity(rule.isEnabled ? 1 : 0.55)
        .padding(.vertical, 2)
    }

    private var detail: String {
        var parts = [rule.style.title, "Sound: \(rule.sound.title)"]
        parts.append(rule.repeatMinutes > 0 ? "Repeats every \(rule.repeatMinutes) min" : "Once")
        return parts.joined(separator: " · ")
    }
}

/// Add / edit sheet for one rule.
struct AlertRuleEditor: View {
    @State var rule: AlertRule
    let onSave: (AlertRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model

    private enum SoundKind: String, CaseIterable, Identifiable {
        case none = "None", system = "System", custom = "Custom file"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Trigger") {
                    Picker("When", selection: $rule.trigger) {
                        ForEach(AlertRule.Trigger.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Slider(value: thresholdBinding, in: 1...100, step: 1)
                        Text("\(rule.threshold)%")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    Text(rule.trigger == .dropsTo
                         ? "Fires while on battery power."
                         : "Fires while plugged in – handy as an unplug reminder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Appearance") {
                    Picker("Style", selection: $rule.style) {
                        ForEach(AlertRule.VisualStyle.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Repeat", selection: $rule.repeatMinutes) {
                        Text("Once").tag(0)
                        ForEach([1, 2, 5, 10, 15, 30], id: \.self) { Text("Every \($0) min").tag($0) }
                    }
                }

                Section("Sound") {
                    Picker("Sound", selection: soundKindBinding) {
                        ForEach(SoundKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if case .system(let name) = rule.sound {
                        Picker("System sound", selection: Binding(
                            get: { name },
                            set: { rule.sound = .system($0); SoundPlayer.play(.system($0), volume: rule.volume) }
                        )) {
                            ForEach(SoundPlayer.systemSounds, id: \.self) { Text($0).tag($0) }
                        }
                    }
                    if case .custom(let path) = rule.sound {
                        HStack {
                            Text((path as NSString).lastPathComponent.isEmpty ? "No file chosen" : (path as NSString).lastPathComponent)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Choose…", action: chooseFile)
                        }
                    }
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                        Slider(value: $rule.volume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                    }
                    .disabled(rule.sound == .none)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Test") { model.alerts.test(rule) }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(rule)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 440, height: 520)
    }

    private var thresholdBinding: Binding<Double> {
        Binding(get: { Double(rule.threshold) }, set: { rule.threshold = Int($0) })
    }

    private var soundKindBinding: Binding<SoundKind> {
        Binding {
            switch rule.sound {
            case .none: .none
            case .system: .system
            case .custom: .custom
            }
        } set: { kind in
            switch kind {
            case .none: rule.sound = .none
            case .system: rule.sound = .system(SoundPlayer.systemSounds.first ?? "Glass")
            case .custom: rule.sound = .custom("")
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            rule.sound = .custom(url.path)
            SoundPlayer.play(rule.sound, volume: rule.volume)
        }
    }
}
