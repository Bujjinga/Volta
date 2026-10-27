//
//  AlertEngine.swift
//  Volta
//

import AppKit
import Foundation
import SwiftUI

/// Evaluates alert rules against every battery update and presents alerts.
///
/// Each rule fires once per *crossing*: after it fires it is disarmed, and it re-arms
/// only when the level moves back past the threshold (e.g. after charging above a
/// low-battery threshold).
final class AlertEngine {
    let store: AlertRuleStore
    private let banner = BannerPresenter()
    private let glow = GlowPresenter()

    /// When set, alerts are recorded here instead of being shown. Used for verification.
    var dryRunLog: [String]?

    private var disarmed: Set<AlertRule.ID> = []
    private var repeatTimers: [AlertRule.ID: Timer] = [:]
    private var latest = BatteryInfo()

    init(store: AlertRuleStore) {
        self.store = store
    }

    // MARK: - Evaluation

    func evaluate(_ info: BatteryInfo) {
        latest = info
        guard info.hasBattery else { return }
        let level = info.percentage
        var triggered: [AlertRule] = []

        for rule in store.rules {
            guard rule.isEnabled else {
                cancelRepeat(rule.id)
                continue
            }
            switch rule.trigger {
            case .dropsTo:
                if level > rule.threshold {
                    rearm(rule.id)
                } else if !info.isOnAC, !disarmed.contains(rule.id) {
                    triggered.append(rule)
                }
                // Plugging in counts as "the user acted": stop repeating.
                if info.isOnAC { cancelRepeat(rule.id) }
            case .reaches:
                if level < rule.threshold {
                    rearm(rule.id)
                } else if info.isOnAC, !disarmed.contains(rule.id) {
                    triggered.append(rule)
                }
                // Unplugging counts as "the user acted".
                if !info.isOnAC { cancelRepeat(rule.id) }
            }
        }

        triggered.forEach { disarmed.insert($0.id) }

        // If several thresholds are crossed at once (e.g. Volta launched at 4%), show only
        // the most urgent one instead of stacking three alerts.
        if let low = triggered.filter({ $0.trigger == .dropsTo }).min(by: { $0.threshold < $1.threshold }) {
            fire(low, level: level)
            scheduleRepeat(for: low)
        }
        if let high = triggered.filter({ $0.trigger == .reaches }).max(by: { $0.threshold < $1.threshold }) {
            fire(high, level: level)
            scheduleRepeat(for: high)
        }
    }

    /// Plays a rule immediately, ignoring its armed state. Used by the "Test" buttons.
    func test(_ rule: AlertRule) {
        fire(rule, level: rule.threshold, isTest: true)
    }

    /// Previews the glow with the current settings (Settings › Effects).
    func previewGlow(_ kind: GlowStyle.Kind) {
        glow.show(GlowStyle.current(kind))
    }

    /// Previews the banner with the current position and duration settings.
    func previewBanner() {
        let content = BannerContent(
            title: "Battery at 20%",
            message: "This is how Volta's banner looks.",
            symbol: "battery.25percent",
            level: 20,
            tint: GlowStyle.current(.low).color
        )
        banner.show(content) {}
    }

    /// Shows a one-off alert that isn't tied to a stored rule (used for device alerts).
    func presentAdHoc(title: String, message: String, symbol: String, level: Int) {
        let content = BannerContent(title: title, message: message, symbol: symbol, level: level, tint: .orange)
        banner.show(content) {}
        if !isQuietTime {
            SoundPlayer.play(.system("Tink"), volume: 0.6)
        }
        if UserDefaults.standard.bool(forKey: SettingsKey.systemNotifications) {
            NotificationSender.send(title: title, body: message)
        }
    }

    // MARK: - Presenting

    private var isQuietTime: Bool {
        UserDefaults.standard.bool(forKey: SettingsKey.respectFocus) && FocusMonitor.isFocused
    }

    private func fire(_ rule: AlertRule, level: Int, isTest: Bool = false) {
        let isLow = rule.trigger == .dropsTo
        let title = isTest ? "Test: \(rule.summary)" : "Battery at \(level)%"
        let quiet = isQuietTime && !isTest

        if dryRunLog != nil {
            dryRunLog?.append("\(rule.summary) @ \(level)%")
            return
        }
        // During Focus/Do Not Disturb we still show the banner, but skip sound and glow.
        if !quiet {
            SoundPlayer.play(rule.sound, volume: rule.volume)
        }
        let glowStyle = GlowStyle.current(isLow ? .low : .full)
        if rule.style.showsBanner || quiet {
            let content = BannerContent(
                title: title,
                message: rule.message,
                symbol: isLow ? "battery.25percent" : "battery.100percent.bolt",
                level: level,
                tint: glowStyle.color
            )
            banner.show(content) { [weak self] in
                // Dismissing the banner is the explicit "I've seen it" action.
                self?.cancelRepeat(rule.id)
            }
        }
        if rule.style.showsGlow, !quiet {
            glow.show(glowStyle)
        }
        if UserDefaults.standard.bool(forKey: SettingsKey.systemNotifications) {
            NotificationSender.send(title: title, body: rule.message)
        }
    }

    // MARK: - Repeating

    private func scheduleRepeat(for rule: AlertRule) {
        cancelRepeat(rule.id)
        guard rule.repeatMinutes > 0 else { return }
        let timer = Timer(timeInterval: TimeInterval(rule.repeatMinutes * 60), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.repeatFired(rule.id) }
        }
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        repeatTimers[rule.id] = timer
    }

    private func repeatFired(_ id: AlertRule.ID) {
        guard let rule = store.rules.first(where: { $0.id == id }), rule.isEnabled else {
            cancelRepeat(id)
            return
        }
        // Only repeat while the condition still holds.
        let stillTrue = switch rule.trigger {
        case .dropsTo: !latest.isOnAC && latest.percentage <= rule.threshold
        case .reaches: latest.isOnAC && latest.percentage >= rule.threshold
        }
        if stillTrue {
            fire(rule, level: latest.percentage)
        } else {
            cancelRepeat(id)
        }
    }

    private func rearm(_ id: AlertRule.ID) {
        disarmed.remove(id)
        cancelRepeat(id)
    }

    private func cancelRepeat(_ id: AlertRule.ID) {
        repeatTimers.removeValue(forKey: id)?.invalidate()
    }
}
