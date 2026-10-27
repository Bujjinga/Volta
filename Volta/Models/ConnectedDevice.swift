//
//  ConnectedDevice.swift
//  Volta
//

import Foundation

/// A peripheral with a battery: Magic Mouse/Keyboard/Trackpad, AirPods, etc.
struct ConnectedDevice: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case mouse, keyboard, trackpad, audio, other

        var symbol: String {
            switch self {
            case .mouse: "magicmouse.fill"
            case .keyboard: "keyboard.fill"
            case .trackpad: "rectangle.and.hand.point.up.left.fill"
            case .audio: "airpods"
            case .other: "dot.radiowaves.left.and.right"
            }
        }

        var settingsKey: String {
            switch self {
            case .mouse, .trackpad: SettingsKey.showMice
            case .keyboard: SettingsKey.showKeyboards
            case .audio: SettingsKey.showAudio
            case .other: SettingsKey.showOtherDevices
            }
        }

        nonisolated static func guess(from text: String) -> Kind {
            let lower = text.lowercased()
            if lower.contains("trackpad") { return .trackpad }
            if lower.contains("mouse") { return .mouse }
            if lower.contains("keyboard") { return .keyboard }
            if ["airpods", "headphone", "headset", "beats", "speaker", "earbuds"].contains(where: lower.contains) { return .audio }
            return .other
        }
    }

    var name: String
    /// "Left", "Right", "Case" for AirPods; `nil` for single-battery devices.
    var part: String?
    var kind: Kind
    var percentage: Int

    var id: String { "\(name)|\(part ?? "")" }

    var displayName: String {
        part.map { "\(name) – \($0)" } ?? name
    }
}
