//
//  HistoryService.swift
//  Volta
//

import Foundation
import SwiftData

/// Records battery history in SwiftData.
///
/// - A level sample at most every 10 minutes (on power-source events, plus a lazy
///   10-minute timer so quiet stretches like "plugged in at 100%" still get logged).
/// - One health snapshot per calendar day.
/// - Level samples older than 7 days are deleted.
final class HistoryService {
    let container: ModelContainer

    private static let sampleInterval: TimeInterval = 10 * 60
    private static let retention: TimeInterval = 7 * 24 * 60 * 60

    private var lastSample: Date?
    private var timer: Timer?
    private var latest = BatteryInfo()

    private var context: ModelContext { container.mainContext }

    init() {
        // Store the database in ~/Library/Application Support/Volta. Without the sandbox,
        // SwiftData's default location is shared with every other unsandboxed app.
        let directory = URL.applicationSupportDirectory.appending(path: "Volta", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: directory.appending(path: "History.store"))

        do {
            container = try ModelContainer(for: LevelSample.self, HealthSnapshot.self, configurations: configuration)
        } catch {
            // Fall back to memory so the app still works if the store is unreadable.
            print("Volta: history store unavailable (\(error)); using in-memory store")
            // swiftlint:disable:next force_try
            container = try! ModelContainer(
                for: LevelSample.self, HealthSnapshot.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }

        var descriptor = FetchDescriptor<LevelSample>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        lastSample = (try? context.fetch(descriptor))?.first?.timestamp
    }

    func start(with info: BatteryInfo) {
        record(info)
        let timer = Timer(timeInterval: Self.sampleInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.record(self.latest, force: true)
            }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Called on every battery change; writes only when a sample is due.
    func record(_ info: BatteryInfo, force: Bool = false) {
        latest = info
        guard info.hasBattery else { return }
        let now = Date.now

        if force || lastSample.map({ now.timeIntervalSince($0) >= Self.sampleInterval }) ?? true {
            context.insert(LevelSample(timestamp: now, percentage: info.percentage, isCharging: info.isCharging))
            lastSample = now
            pruneOldSamples(before: now.addingTimeInterval(-Self.retention))
        }
        saveDailySnapshotIfNeeded(info, now: now)
        try? context.save()
    }

    private func pruneOldSamples(before cutoff: Date) {
        try? context.delete(model: LevelSample.self, where: #Predicate { $0.timestamp < cutoff })
    }

    private func saveDailySnapshotIfNeeded(_ info: BatteryInfo, now: Date) {
        guard let health = info.healthPercent, let cycles = info.cycleCount, let capacity = info.rawMaxCapacity else { return }
        let startOfDay = Calendar.current.startOfDay(for: now)
        var descriptor = FetchDescriptor<HealthSnapshot>(predicate: #Predicate { $0.date >= startOfDay })
        descriptor.fetchLimit = 1
        guard (try? context.fetchCount(descriptor)) == 0 else { return }
        context.insert(HealthSnapshot(date: now, healthPercent: health, cycleCount: cycles, maxCapacity: capacity))
    }

    // MARK: - Export

    func exportCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var lines = ["type,timestamp,percentage,is_charging,health_percent,cycle_count,max_capacity_mah"]

        let samples = (try? context.fetch(FetchDescriptor<LevelSample>(sortBy: [SortDescriptor(\.timestamp)]))) ?? []
        for sample in samples {
            lines.append("level,\(formatter.string(from: sample.timestamp)),\(sample.percentage),\(sample.isCharging),,,")
        }
        let snapshots = (try? context.fetch(FetchDescriptor<HealthSnapshot>(sortBy: [SortDescriptor(\.date)]))) ?? []
        for snapshot in snapshots {
            lines.append("health,\(formatter.string(from: snapshot.date)),,,\(String(format: "%.2f", snapshot.healthPercent)),\(snapshot.cycleCount),\(snapshot.maxCapacity)")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
