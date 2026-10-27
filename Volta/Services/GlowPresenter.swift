//
//  GlowPresenter.swift
//  Volta
//

import AppKit
import SwiftUI

/// User-tunable glow parameters.
struct GlowStyle: Equatable {
    var color: Color
    /// 0.2 … 1
    var intensity: Double = SettingsDefaults.glowIntensity
    /// Thickness multiplier, 0.5 … 2
    var width: Double = SettingsDefaults.glowWidth
    /// 1 … 6
    var pulses: Int = SettingsDefaults.glowPulses
    /// Speed multiplier, 0.5 (slow) … 2 (fast)
    var speed: Double = SettingsDefaults.glowSpeed

    enum Kind { case low, full }

    /// Reads the current settings for a low-battery or fully-charged glow.
    static func current(_ kind: Kind) -> GlowStyle {
        let defaults = UserDefaults.standard
        let colorKey = kind == .low ? SettingsKey.glowLowColor : SettingsKey.glowFullColor
        let fallback = kind == .low ? SettingsDefaults.glowLowColor : SettingsDefaults.glowFullColor
        return GlowStyle(
            color: Color(hex: defaults.string(forKey: colorKey) ?? fallback),
            intensity: defaults.double(forKey: SettingsKey.glowIntensity),
            width: defaults.double(forKey: SettingsKey.glowWidth),
            pulses: defaults.integer(forKey: SettingsKey.glowPulses),
            speed: defaults.double(forKey: SettingsKey.glowSpeed)
        )
    }
}

/// Pulses a soft colored glow around the edges of every connected display.
///
/// The windows are click-through (`ignoresMouseEvents`) and sit above normal windows,
/// so the glow never blocks work.
final class GlowPresenter {
    private var windows: [NSWindow] = []
    /// Bumped on every show so a finishing older glow doesn't close a newer one.
    private var generation = 0

    func show(_ style: GlowStyle) {
        dismiss()
        generation += 1
        let current = generation
        for screen in NSScreen.screens {
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.setFrame(screen.frame, display: false)
            window.level = .screenSaver
            window.ignoresMouseEvents = true
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.contentView = NSHostingView(rootView: GlowView(style: style) { [weak self] in
                guard let self, self.generation == current else { return }
                self.dismiss()
            })
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    func dismiss() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

struct GlowView: View {
    let style: GlowStyle
    let onFinished: () -> Void

    @State private var level = 0.0

    var body: some View {
        GlowEdges(color: style.color, width: style.width)
            .opacity(level * style.intensity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .task { await pulse() }
    }

    private func pulse() async {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let count = reduceMotion ? 1 : max(1, style.pulses)
        // One pulse ≈ 1.25 s at 1× speed.
        let unit = 0.6 / max(0.25, style.speed)
        for index in 0..<count {
            withAnimation(.easeInOut(duration: unit)) { level = 1 }
            try? await Task.sleep(for: .seconds(reduceMotion ? 1.5 : unit * 1.1))
            let isLast = index == count - 1
            withAnimation(.easeInOut(duration: isLast ? unit * 1.6 : unit)) { level = isLast ? 0 : 0.2 }
            try? await Task.sleep(for: .seconds(isLast ? unit * 1.7 : unit))
        }
        onFinished()
    }
}

/// The glow at full strength: color fades from each screen edge toward the center,
/// with a thin bright rim. Gradients (rather than a blurred stroke) keep the color
/// strongest right at the edge instead of losing half of it off-screen.
struct GlowEdges: View {
    let color: Color
    /// Thickness multiplier.
    var width: Double = 1

    var body: some View {
        let depth = 110 * width
        let fade = Gradient(stops: [
            .init(color: color.opacity(0.95), location: 0),
            .init(color: color.opacity(0.45), location: 0.35),
            .init(color: color.opacity(0), location: 1),
        ])
        ZStack {
            edge(fade, from: .top, to: .bottom).frame(height: depth).frame(maxHeight: .infinity, alignment: .top)
            edge(fade, from: .bottom, to: .top).frame(height: depth).frame(maxHeight: .infinity, alignment: .bottom)
            edge(fade, from: .leading, to: .trailing).frame(width: depth).frame(maxWidth: .infinity, alignment: .leading)
            edge(fade, from: .trailing, to: .leading).frame(width: depth).frame(maxWidth: .infinity, alignment: .trailing)
            Rectangle()
                .strokeBorder(color, lineWidth: 5 * width)
                .blur(radius: 4 * width)
        }
    }

    private func edge(_ gradient: Gradient, from start: UnitPoint, to end: UnitPoint) -> some View {
        LinearGradient(gradient: gradient, startPoint: start, endPoint: end)
    }
}

#Preview("Glow") {
    // A static frame of the glow at full brightness over a stand-in desktop.
    ZStack {
        LinearGradient(colors: [.indigo, .teal], startPoint: .topLeading, endPoint: .bottomTrailing)
        GlowEdges(color: .red)
            .opacity(SettingsDefaults.glowIntensity)
    }
    .frame(width: 640, height: 400)
}
