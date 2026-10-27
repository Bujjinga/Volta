//
//  BatteryIconView.swift
//  Volta
//

import SwiftUI

/// The user's level colors and thresholds.
struct IconPalette: Equatable {
    var high: Color
    var medium: Color
    var low: Color
    var charging: Color
    var useChargingColor: Bool
    var greenAbove: Int
    var redAtOrBelow: Int

    func color(for percentage: Int, isCharging: Bool = false) -> Color {
        if isCharging && useChargingColor { return charging }
        if percentage <= redAtOrBelow { return low }
        if percentage > greenAbove { return high }
        return medium
    }
}

/// Reads the palette from `@AppStorage`, so any view that uses it updates live.
struct PaletteSettings: DynamicProperty {
    @AppStorage(SettingsKey.colorHigh) private var high = SettingsDefaults.colorHigh
    @AppStorage(SettingsKey.colorMedium) private var medium = SettingsDefaults.colorMedium
    @AppStorage(SettingsKey.colorLow) private var low = SettingsDefaults.colorLow
    @AppStorage(SettingsKey.colorCharging) private var charging = SettingsDefaults.colorCharging
    @AppStorage(SettingsKey.useChargingColor) private var useChargingColor = false
    @AppStorage(SettingsKey.greenAbove) private var greenAbove = SettingsDefaults.greenAbove
    @AppStorage(SettingsKey.redAtOrBelow) private var redAtOrBelow = SettingsDefaults.redAtOrBelow

    var palette: IconPalette {
        IconPalette(
            high: Color(hex: high), medium: Color(hex: medium), low: Color(hex: low),
            charging: Color(hex: charging), useChargingColor: useChargingColor,
            greenAbove: greenAbove, redAtOrBelow: redAtOrBelow
        )
    }
}

/// Shape, size, and labeling of the battery icon.
struct BatteryIconStyle: Equatable {
    var shape: IconShape = .rounded
    var percent: IconPercentPlacement = .inside
    var size: IconSize = .regular
    var showBolt = true
}

struct IconStyleSettings: DynamicProperty {
    @AppStorage(SettingsKey.iconShape) private var shape = IconShape.rounded
    @AppStorage(SettingsKey.iconPercent) private var percent = IconPercentPlacement.inside
    @AppStorage(SettingsKey.iconSize) private var size = IconSize.regular
    @AppStorage(SettingsKey.iconShowBolt) private var showBolt = true

    var style: BatteryIconStyle {
        BatteryIconStyle(shape: shape, percent: percent, size: size, showBolt: showBolt)
    }
}

/// A compact battery icon. With "inside" placement the number is knocked out of the
/// fill, like the iPhone status bar.
///
/// Used both as the menu bar icon (rendered to an `NSImage`) and inside the app.
struct BatteryIconView: View {
    var percentage: Int
    var isCharging: Bool
    /// `nil` draws in solid black for use as a template image.
    var tint: Color?
    var style = BatteryIconStyle()
    /// Overrides `style.size` (the popover shows a bigger battery).
    var height: CGFloat?

    private var bodyHeight: CGFloat { height ?? style.size.height }
    private var bodyWidth: CGFloat { bodyHeight * (style.shape == .capsule ? 2.15 : 2) }
    private var fraction: CGFloat { CGFloat(min(max(percentage, 0), 100)) / 100 }
    private var color: Color { tint ?? .black }

    private var cornerRadius: CGFloat {
        switch style.shape {
        case .rounded: bodyHeight * 0.3
        case .capsule: bodyHeight / 2
        case .outline: bodyHeight * 0.28
        }
    }

    var body: some View {
        HStack(spacing: bodyHeight * 0.15) {
            if style.percent == .beside {
                Text("\(percentage)%")
                    .font(.system(size: bodyHeight * 0.95, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
            HStack(spacing: bodyHeight * 0.08) {
                batteryBody
                terminal
            }
            if isCharging && style.showBolt {
                Image(systemName: "bolt.fill")
                    .font(.system(size: bodyHeight * 0.78, weight: .bold))
                    .foregroundStyle(color)
            }
        }
        .compositingGroup()
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var batteryBody: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        ZStack(alignment: .leading) {
            if style.shape == .outline {
                // Classic Mac battery: an outline with an inset fill.
                let inset = max(1.5, bodyHeight * 0.16)
                shape.strokeBorder(color.opacity(0.55), lineWidth: max(1, bodyHeight * 0.09))
                // With the number inside, soften the fill so the solid digits sit on top.
                RoundedRectangle(cornerRadius: max(1, cornerRadius - inset), style: .continuous)
                    .fill(color.opacity(style.percent == .inside ? 0.4 : 1))
                    .frame(width: max(0, (bodyWidth - inset * 2) * fraction))
                    .padding(inset)
            } else {
                shape.fill(color.opacity(0.35))
                Rectangle()
                    .fill(color)
                    .frame(width: bodyWidth * fraction)
            }
        }
        .frame(width: bodyWidth, height: bodyHeight)
        .clipShape(shape)
        .overlay {
            if style.percent == .inside { insideLabel }
        }
    }

    /// Filled shapes knock the number out of the fill (iPhone style). The outline shape
    /// draws a solid number over its softened fill instead.
    @ViewBuilder
    private var insideLabel: some View {
        let label = Text("\(percentage)")
            .font(.system(size: bodyHeight * (style.shape == .outline ? 0.66 : 0.78), weight: .bold, design: .rounded))
            .monospacedDigit()
            .minimumScaleFactor(0.5)
            .frame(width: bodyWidth, height: bodyHeight)
        if style.shape == .outline {
            label.foregroundStyle(color)
        } else {
            label.blendMode(.destinationOut)
        }
    }

    private var terminal: some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: 0,
            bottomTrailingRadius: bodyHeight * 0.15, topTrailingRadius: bodyHeight * 0.15
        )
        .fill(color.opacity(0.45))
        .frame(width: bodyHeight * 0.13, height: bodyHeight * 0.36)
    }
}

#Preview {
    let palette = IconPalette(
        high: Color(hex: SettingsDefaults.colorHigh), medium: Color(hex: SettingsDefaults.colorMedium),
        low: Color(hex: SettingsDefaults.colorLow), charging: Color(hex: SettingsDefaults.colorCharging),
        useChargingColor: false, greenAbove: 50, redAtOrBelow: 20
    )
    Grid(horizontalSpacing: 18, verticalSpacing: 14) {
        ForEach(IconShape.allCases) { shape in
            GridRow {
                ForEach(IconPercentPlacement.allCases) { percent in
                    BatteryIconView(
                        percentage: [82, 35, 9][IconPercentPlacement.allCases.firstIndex(of: percent) ?? 0],
                        isCharging: percent == .beside,
                        tint: palette.color(for: [82, 35, 9][IconPercentPlacement.allCases.firstIndex(of: percent) ?? 0]),
                        style: BatteryIconStyle(shape: shape, percent: percent, size: .large),
                        height: 24
                    )
                }
            }
        }
    }
    .padding()
}
