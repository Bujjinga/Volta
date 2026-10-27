//
//  SoundPlayer.swift
//  Volta
//

import AppKit

/// Plays alert sounds with NSSound.
enum SoundPlayer {
    /// The built-in alert sounds in /System/Library/Sounds (Basso, Glass, Hero, …).
    static let systemSounds: [String] = {
        let directory = URL(fileURLWithPath: "/System/Library/Sounds")
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        let names = files.map { $0.deletingPathExtension().lastPathComponent }
        return names.isEmpty ? ["Glass", "Funk", "Hero", "Sosumi", "Ping", "Tink"] : names.sorted()
    }()

    /// Kept alive so playback isn't cut off when the local goes out of scope.
    private static var current: NSSound?

    /// Plays `sound` at `volume` × the master volume, unless sounds are muted globally.
    static func play(_ sound: AlertRule.Sound, volume: Double) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.soundsMuted) else { return }
        let volume = volume * defaults.double(forKey: SettingsKey.masterVolume)
        current?.stop()
        let nsSound: NSSound? = switch sound {
        case .none: nil
        case .system(let name): NSSound(named: NSSound.Name(name))
        case .custom(let path): NSSound(contentsOf: URL(fileURLWithPath: path), byReference: true)
        }
        guard let nsSound else { return }
        nsSound.volume = Float(min(max(volume, 0), 1))
        nsSound.play()
        current = nsSound
    }
}
