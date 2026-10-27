//
//  AlertRuleStore.swift
//  Volta
//

import Foundation
import Observation

/// Persists alert rules as JSON in UserDefaults.
@Observable
final class AlertRuleStore {
    var rules: [AlertRule] {
        didSet { save() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: SettingsKey.alertRules),
           let decoded = try? JSONDecoder().decode([AlertRule].self, from: data) {
            rules = decoded
        } else {
            rules = AlertRule.defaults
        }
    }

    func add(_ rule: AlertRule) { rules.append(rule) }

    func update(_ rule: AlertRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
        rules[index] = rule
    }

    func delete(_ ids: Set<AlertRule.ID>) {
        rules.removeAll { ids.contains($0.id) }
    }

    func resetToDefaults() { rules = AlertRule.defaults }

    private func save() {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        UserDefaults.standard.set(data, forKey: SettingsKey.alertRules)
    }
}
