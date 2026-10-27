//
//  AlertRule.swift
//  Volta
//

import Foundation

/// A user-defined battery alert.
struct AlertRule: Codable, Identifiable, Hashable {
    enum Trigger: String, Codable, CaseIterable, Identifiable {
        /// Fires while discharging when the level falls to the threshold or below.
        case dropsTo
        /// Fires while on AC power when the level rises to the threshold or above.
        case reaches

        var id: String { rawValue }
        var title: String {
            switch self {
            case .dropsTo: "Battery drops to"
            case .reaches: "Battery reaches"
            }
        }
    }

    enum VisualStyle: String, Codable, CaseIterable, Identifiable {
        case banner, glow, both
        var id: String { rawValue }
        var title: String {
            switch self {
            case .banner: "Pill banner"
            case .glow: "Screen glow"
            case .both: "Banner + glow"
            }
        }
        var showsBanner: Bool { self != .glow }
        var showsGlow: Bool { self != .banner }
    }

    enum Sound: Codable, Hashable {
        case none
        case system(String)
        /// Absolute path to an audio file the user picked.
        case custom(String)

        var title: String {
            switch self {
            case .none: "None"
            case .system(let name): name
            case .custom(let path): (path as NSString).lastPathComponent
            }
        }
    }

    var id = UUID()
    var isEnabled = true
    var trigger: Trigger
    var threshold: Int
    var sound: Sound = .system("Glass")
    /// 0…1
    var volume: Double = 0.8
    var style: VisualStyle = .both
    /// 0 means alert once per crossing.
    var repeatMinutes = 0

    var summary: String { "\(trigger.title) \(threshold)%" }

    var message: String {
        switch trigger {
        case .dropsTo: threshold <= 10 ? "Plug in now to avoid losing work." : "Time to find your charger."
        case .reaches: "Unplug to help preserve battery health."
        }
    }

    static let defaults: [AlertRule] = [
        AlertRule(trigger: .dropsTo, threshold: 20, sound: .system("Glass"), style: .both),
        AlertRule(trigger: .dropsTo, threshold: 10, sound: .system("Funk"), style: .both, repeatMinutes: 5),
        AlertRule(trigger: .dropsTo, threshold: 5, sound: .system("Sosumi"), volume: 1, style: .both, repeatMinutes: 2),
        AlertRule(isEnabled: false, trigger: .reaches, threshold: 80, sound: .system("Hero"), style: .banner),
    ]
}
