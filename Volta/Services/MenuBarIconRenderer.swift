//
//  MenuBarIconRenderer.swift
//  Volta
//

import AppKit
import SwiftUI

/// Renders `BatteryIconView` into an `NSImage` for the menu bar, caching the result so
/// a new image is produced only when the visible inputs actually change.
final class MenuBarIconRenderer {
    struct Key: Equatable {
        var percentage: Int
        var isCharging: Bool
        var theme: IconTheme
        var style: BatteryIconStyle
        var palette: IconPalette
    }

    private var cachedKey: Key?
    private var cachedImage: NSImage?

    func image(for key: Key) -> NSImage {
        if key == cachedKey, let cachedImage { return cachedImage }

        let tint: Color? = key.theme == .colored
            ? key.palette.color(for: key.percentage, isCharging: key.isCharging)
            : nil
        let renderer = ImageRenderer(content: BatteryIconView(
            percentage: key.percentage,
            isCharging: key.isCharging,
            tint: tint,
            style: key.style
        ))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        let image = renderer.nsImage ?? NSImage(systemSymbolName: "battery.100", accessibilityDescription: nil) ?? NSImage()
        // A template image is recolored by AppKit to match the menu bar (black or white).
        image.isTemplate = key.theme == .monochrome
        image.accessibilityDescription = "Battery \(key.percentage)%\(key.isCharging ? ", charging" : "")"

        cachedKey = key
        cachedImage = image
        return image
    }
}

/// The view MenuBarExtra uses as its label.
struct MenuBarLabel: View {
    let battery: BatteryService
    let renderer: MenuBarIconRenderer

    @AppStorage(SettingsKey.iconTheme) private var theme = IconTheme.colored
    private var iconStyle = IconStyleSettings()
    private var paletteSettings = PaletteSettings()

    init(battery: BatteryService, renderer: MenuBarIconRenderer) {
        self.battery = battery
        self.renderer = renderer
    }

    var body: some View {
        let info = battery.info
        if !info.hasBattery {
            Image(systemName: "powerplug.fill")
        } else if theme == .textOnly {
            Text(info.isCharging && iconStyle.style.showBolt ? "⚡︎\(info.percentage)%" : "\(info.percentage)%")
                .monospacedDigit()
        } else {
            Image(nsImage: renderer.image(for: .init(
                percentage: info.percentage,
                isCharging: info.isCharging,
                theme: theme,
                style: iconStyle.style,
                palette: paletteSettings.palette
            )))
        }
    }
}
