//
//  HistoryModels.swift
//  Volta
//

import Foundation
import SwiftData

/// Battery level logged every 10 minutes and kept for 7 days.
@Model
final class LevelSample {
    var timestamp: Date
    var percentage: Int
    var isCharging: Bool

    init(timestamp: Date = .now, percentage: Int, isCharging: Bool) {
        self.timestamp = timestamp
        self.percentage = percentage
        self.isCharging = isCharging
    }
}

/// Long-term health record, saved once per day and kept indefinitely.
@Model
final class HealthSnapshot {
    var date: Date
    var healthPercent: Double
    var cycleCount: Int
    /// mAh
    var maxCapacity: Int

    init(date: Date = .now, healthPercent: Double, cycleCount: Int, maxCapacity: Int) {
        self.date = date
        self.healthPercent = healthPercent
        self.cycleCount = cycleCount
        self.maxCapacity = maxCapacity
    }
}
