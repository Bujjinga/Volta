//
//  HealthView.swift
//  Volta
//

import AppKit
import Charts
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The "Health" tab: charts for level, health, and cycles, plus CSV export.
struct HealthView: View {
    @Environment(AppModel.self) private var model
    @Environment(BatteryService.self) private var battery

    @Query(sort: \LevelSample.timestamp) private var samples: [LevelSample]
    @Query(sort: \HealthSnapshot.date) private var snapshots: [HealthSnapshot]

    private var last24Hours: [LevelSample] {
        let cutoff = Date.now.addingTimeInterval(-24 * 60 * 60)
        return samples.filter { $0.timestamp >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            temperatureRow
            levelChart
            HStack(alignment: .top, spacing: 12) {
                healthChart
                cycleChart
            }
            Text("Health is the raw full-charge capacity ÷ design capacity. macOS smooths its own figure over time, so System Settings may show a slightly different value.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Export History as CSV…", systemImage: "square.and.arrow.up", action: exportCSV)
                    .controlSize(.small)
            }
        }
    }

    // MARK: - Pieces

    private var temperatureRow: some View {
        HStack {
            Label("Temperature", systemImage: "thermometer.medium")
            Spacer()
            if let temperature = battery.info.temperature {
                Text(String(format: "%.1f °C", temperature))
                    .monospacedDigit()
                if temperature > 40 {
                    Label("Hot", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                        .help("Sustained temperatures above 40 °C age the battery faster.")
                }
            } else {
                Text("–").foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }

    private var levelChart: some View {
        ChartCard(title: "Battery level – last 24 hours") {
            if last24Hours.count < 2 {
                placeholder("Collecting data… a sample is saved every 10 minutes.")
            } else {
                Chart(last24Hours) { sample in
                    AreaMark(x: .value("Time", sample.timestamp), y: .value("Level", sample.percentage))
                        .foregroundStyle(.linearGradient(colors: [.green.opacity(0.35), .green.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", sample.timestamp), y: .value("Level", sample.percentage))
                        .foregroundStyle(.green)
                        .interpolationMethod(.monotone)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel("\(value.as(Int.self) ?? 0)%")
                    }
                }
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { _ in AxisGridLine(); AxisValueLabel(format: .dateTime.hour()) } }
                .frame(height: 110)
            }
        }
    }

    private var healthChart: some View {
        ChartCard(title: "Health") {
            if snapshots.count < 2 {
                placeholder(snapshots.first.map { String(format: "%.0f%% today", $0.healthPercent) } ?? "No data yet")
            } else {
                Chart(snapshots) { snapshot in
                    LineMark(x: .value("Date", snapshot.date), y: .value("Health", snapshot.healthPercent))
                        .foregroundStyle(.pink)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
                .frame(height: 80)
            }
        }
    }

    private var cycleChart: some View {
        ChartCard(title: "Cycle count") {
            if snapshots.count < 2 {
                placeholder(snapshots.first.map { "\($0.cycleCount) cycles" } ?? "No data yet")
            } else {
                Chart(snapshots) { snapshot in
                    LineMark(x: .value("Date", snapshot.date), y: .value("Cycles", snapshot.cycleCount))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.stepEnd)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.narrow)) } }
                .frame(height: 80)
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
    }

    private func exportCSV() {
        let csv = model.history.exportCSV()
        NSApplication.shared.activate()
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "Volta History \(Date.now.formatted(.iso8601.year().month().day())).csv"
        if panel.runModal() == .OK, let url = panel.url {
            try? csv.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

struct ChartCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
    }
}
