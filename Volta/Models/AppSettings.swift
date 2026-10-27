//
//  AppSettings.swift
//  Volta
//

import AppKit
import SwiftUI

/// UserDefaults keys shared by `@AppStorage` properties and services.
enum SettingsKey {
    // Menu bar icon
    static let iconTheme = "iconTheme"
    static let iconShape = "iconShape"
    static let iconPercent = "iconPercent"
    static let iconSize = "iconSize"
    static let iconShowBolt = "iconShowBolt"
    static let greenAbove = "greenAbove"
    static let redAtOrBelow = "redAtOrBelow"
    static let colorHigh = "colorHigh"
    static let colorMedium = "colorMedium"
    static let colorLow = "colorLow"
    static let colorCharging = "colorCharging"
    static let useChargingColor = "useChargingColor"

    // Alerts
    static let respectFocus = "respectFocus"
    static let systemNotifications = "systemNotifications"
    static let alertRules = "alertRules"

    // Glow
    static let glowLowColor = "glowLowColor"
    static let glowFullColor = "glowFullColor"
    static let glowIntensity = "glowIntensity"
    static let glowWidth = "glowWidth"
    static let glowPulses = "glowPulses"
    static let glowSpeed = "glowSpeed"

    // Banner
    static let bannerPosition = "bannerPosition"
    static let bannerDuration = "bannerDuration"

    // Sound
    static let soundsMuted = "soundsMuted"
    static let masterVolume = "masterVolume"

    // Charging
    static let chargeLimitEnabled = "chargeLimitEnabled"
    static let chargeLimit = "chargeLimit"
    static let sailingMode = "sailingMode"

    // Devices
    static let showMice = "showMice"
    static let showKeyboards = "showKeyboards"
    static let showAudio = "showAudio"
    static let showOtherDevices = "showOtherDevices"
    static let deviceAlertsEnabled = "deviceAlertsEnabled"
    static let deviceAlertThreshold = "deviceAlertThreshold"
}

/// Default values registered at launch so services and views agree.
enum SettingsDefaults {
    static let greenAbove = 50
    static let redAtOrBelow = 20
    static let chargeLimit = 80
    static let deviceAlertThreshold = 15

    static let colorHigh = "#34C759"
    static let colorMedium = "#FFCC00"
    static let colorLow = "#FF3B30"
    static let colorCharging = "#34C759"
    static let glowLowColor = "#FF3B30"
    static let glowFullColor = "#34C759"
    static let glowIntensity = 0.85
    static let glowWidth = 1.0
    static let glowPulses = 3
    static let glowSpeed = 1.0
    static let bannerDuration = 12.0
    static let masterVolume = 1.0

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.iconTheme: IconTheme.colored.rawValue,
            SettingsKey.iconShape: IconShape.rounded.rawValue,
            SettingsKey.iconPercent: IconPercentPlacement.inside.rawValue,
            SettingsKey.iconSize: IconSize.regular.rawValue,
            SettingsKey.iconShowBolt: true,
            SettingsKey.greenAbove: greenAbove,
            SettingsKey.redAtOrBelow: redAtOrBelow,
            SettingsKey.colorHigh: colorHigh,
            SettingsKey.colorMedium: colorMedium,
            SettingsKey.colorLow: colorLow,
            SettingsKey.colorCharging: colorCharging,
            SettingsKey.useChargingColor: false,
            SettingsKey.respectFocus: true,
            SettingsKey.systemNotifications: false,
            SettingsKey.glowLowColor: glowLowColor,
            SettingsKey.glowFullColor: glowFullColor,
            SettingsKey.glowIntensity: glowIntensity,
            SettingsKey.glowWidth: glowWidth,
            SettingsKey.glowPulses: glowPulses,
            SettingsKey.glowSpeed: glowSpeed,
            SettingsKey.bannerPosition: BannerPosition.topCenter.rawValue,
            SettingsKey.bannerDuration: bannerDuration,
            SettingsKey.soundsMuted: false,
            SettingsKey.masterVolume: masterVolume,
            SettingsKey.chargeLimitEnabled: false,
            SettingsKey.chargeLimit: chargeLimit,
            SettingsKey.sailingMode: false,
            SettingsKey.showMice: true,
            SettingsKey.showKeyboards: true,
            SettingsKey.showAudio: true,
            SettingsKey.showOtherDevices: true,
            SettingsKey.deviceAlertsEnabled: false,
            SettingsKey.deviceAlertThreshold: deviceAlertThreshold,
        ])
    }

    /// Resets every appearance-related setting (icon, glow, banner, sound).
    static func resetAppearance() {
        let keys = [
            SettingsKey.iconTheme, SettingsKey.iconShape, SettingsKey.iconPercent, SettingsKey.iconSize,
            SettingsKey.iconShowBolt, SettingsKey.greenAbove, SettingsKey.redAtOrBelow,
            SettingsKey.colorHigh, SettingsKey.colorMedium, SettingsKey.colorLow, SettingsKey.colorCharging,
            SettingsKey.useChargingColor, SettingsKey.glowLowColor, SettingsKey.glowFullColor,
            SettingsKey.glowIntensity, SettingsKey.glowWidth, SettingsKey.glowPulses, SettingsKey.glowSpeed,
            SettingsKey.bannerPosition, SettingsKey.bannerDuration, SettingsKey.soundsMuted, SettingsKey.masterVolume,
        ]
        keys.forEach(UserDefaults.standard.removeObject(forKey:))
    }
}

// MARK: - Menu bar icon options

/// How the menu bar icon is colored.
enum IconTheme: String, CaseIterable, Identifiable {
    /// Template image that follows the menu bar's light/dark color.
    case monochrome
    /// Green / yellow / red fill.
    case colored
    /// Just "85%".
    case textOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .monochrome: "Monochrome"
        case .colored: "Colored"
        case .textOnly: "Text only"
        }
    }
}

enum IconShape: String, CaseIterable, Identifiable {
    /// iPhone-style rounded rectangle, filled.
    case rounded
    /// Fully rounded pill, filled.
    case capsule
    /// Classic Mac outline with an inset fill.
    case outline

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rounded: "Rounded"
        case .capsule: "Pill"
        case .outline: "Outline"
        }
    }
}

enum IconPercentPlacement: String, CaseIterable, Identifiable {
    case inside, beside, hidden
    var id: String { rawValue }
    var title: String {
        switch self {
        case .inside: "Inside"
        case .beside: "Beside"
        case .hidden: "Hidden"
        }
    }
}

enum IconSize: String, CaseIterable, Identifiable {
    case small, regular, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// Battery body height in points. The menu bar is 24 pt tall.
    var height: CGFloat {
        switch self {
        case .small: 11
        case .regular: 13
        case .large: 15
        }
    }
}

// MARK: - Alert presentation options

enum BannerPosition: String, CaseIterable, Identifiable {
    case topCenter, topRight, bottomRight
    var id: String { rawValue }
    var title: String {
        switch self {
        case .topCenter: "Top center"
        case .topRight: "Top right"
        case .bottomRight: "Bottom right"
        }
    }
}

// MARK: - Color storage

extension Color {
    /// Parses "#RRGGBB". Falls back to gray for malformed strings.
    init(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let value = UInt32(digits, radix: 16) ?? 0x808080
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// "#RRGGBB" in sRGB, suitable for UserDefaults.
    var hexString: String {
        let color = NSColor(self).usingColorSpace(.sRGB) ?? .gray
        let red = Int((color.redComponent * 255).rounded())
        let green = Int((color.greenComponent * 255).rounded())
        let blue = Int((color.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

extension Binding where Value == String {
    /// Bridges a hex string (from `@AppStorage`) to a `ColorPicker`.
    var color: Binding<Color> {
        Binding<Color>(get: { Color(hex: wrappedValue) }, set: { wrappedValue = $0.hexString })
    }
}
