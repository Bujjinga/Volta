//
//  EnergyView.swift
//  Volta
//

import SwiftUI

/// The "Energy" tab. Sampling starts when it appears and stops when it disappears.
struct EnergyView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let energy = model.energy
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Using significant energy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if energy.isLoading {
                    ProgressView().controlSize(.mini)
                }
            }

            if energy.apps.isEmpty && !energy.isLoading {
                Text("No apps are using significant energy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                let maxImpact = max(energy.apps.first?.impact ?? 1, 1)
                ForEach(energy.apps) { app in
                    HStack(spacing: 8) {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 20, height: 20)
                        Text(app.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        ImpactBar(fraction: app.impact / maxImpact)
                            .frame(width: 70, height: 5)
                        Text(String(format: "%.1f", app.impact))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .font(.callout)
                }
                .animation(.snappy, value: energy.apps.map(\.id))
            }

            Text("Energy Impact as measured by `top` (the same metric as Activity Monitor). Helpers are grouped under their app.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { energy.start() }
        .onDisappear { energy.stop() }
    }
}

struct ImpactBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(fraction > 0.66 ? Color.orange : Color.accentColor)
                    .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
    }
}
