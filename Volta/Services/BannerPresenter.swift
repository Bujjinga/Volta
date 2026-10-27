//
//  BannerPresenter.swift
//  Volta
//

import AppKit
import SwiftUI

struct BannerContent {
    var title: String
    var message: String
    var symbol: String
    var level: Int
    var tint: Color
}

/// A panel that can never become key or main, so showing it never steals focus
/// from whatever the user is typing in.
final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the pill banner at the top-center of the active screen.
final class BannerPresenter {
    private var panel: NonActivatingPanel?
    private var autoHideTask: Task<Void, Never>?
    /// Vertical distance the banner slides; negative for bottom positions.
    private var slideOffset: CGFloat = 40

    func show(_ content: BannerContent, onDismiss: @escaping () -> Void) {
        hide(animated: false)

        let rootView = BannerView(content: content) { [weak self] in
            self?.hide(animated: true)
            onDismiss()
        }
        let hosting = NSHostingView(rootView: rootView)
        let size = hosting.fittingSize

        let panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            // .nonactivatingPanel lets the dismiss button receive clicks without
            // activating Volta or taking keyboard focus.
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = hosting

        // Place it on the screen the pointer is on, at the user's chosen position.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let defaults = UserDefaults.standard
        let position = BannerPosition(rawValue: defaults.string(forKey: SettingsKey.bannerPosition) ?? "") ?? .topCenter
        let target: NSPoint = switch position {
        case .topCenter: NSPoint(x: visible.midX - size.width / 2, y: visible.maxY - size.height)
        case .topRight: NSPoint(x: visible.maxX - size.width, y: visible.maxY - size.height)
        case .bottomRight: NSPoint(x: visible.maxX - size.width, y: visible.minY)
        }
        // Slide in from the nearest screen edge.
        slideOffset = position == .bottomRight ? -40 : 40
        let start = NSPoint(x: target.x, y: target.y + slideOffset)

        // With Reduce Motion on, fade in place instead of sliding.
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.setFrameOrigin(reduceMotion ? target : start)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? 0.2 : 0.45
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1.1)
            // The window animator only animates setFrame(_:display:), not setFrameOrigin.
            panel.animator().setFrame(NSRect(origin: target, size: size), display: true)
            panel.animator().alphaValue = 1
        }
        self.panel = panel

        // Banners tidy themselves away (0 = stay until dismissed); repeats keep running.
        let duration = defaults.double(forKey: SettingsKey.bannerDuration)
        guard duration > 0 else { return }
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.hide(animated: true)
        }
    }

    func hide(animated: Bool) {
        autoHideTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        guard animated else {
            panel.orderOut(nil)
            return
        }
        let frame = panel.frame.offsetBy(dx: 0, dy: slideOffset)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(frame, display: true)
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }
}

/// The pill itself.
struct BannerView: View {
    let content: BannerContent
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: content.symbol)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(content.tint)
                .symbolRenderingMode(.hierarchical)
            VStack(alignment: .leading, spacing: 1) {
                Text(content.title)
                    .font(.system(.headline, design: .rounded))
                Text(content.message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 10)
        .frame(width: 380)
        .background(VisualEffectBlur(material: .hudWindow).clipShape(Capsule()))
        .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
        .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        // Room for the shadow inside the transparent panel.
        .padding(20)
    }
}

/// Real behind-window blur, which SwiftUI materials can't do inside a transparent panel.
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

#Preview("Banner") {
    BannerView(
        content: BannerContent(title: "Battery at 20%", message: "Time to find your charger.", symbol: "battery.25percent", level: 20, tint: .red),
        onDismiss: {}
    )
    .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
}
