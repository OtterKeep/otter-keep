import Foundation
import OtterKeepDomain

/// Health and capacity risk status for storage volumes.
public enum ForecastHealthStatus: String, Codable, Sendable {
    /// Safe capacity with healthy margins (> 60 days remaining or steady state).
    case healthy = "healthy"
    /// Moderate consumption rate (30 to 60 days remaining).
    case moderate = "moderate"
    /// Warning threshold reached (7 to 30 days remaining or storage < 15%).
    case warning = "warning"
    /// Critical shortage (< 7 days remaining, storage < 5%, or quota exceeded).
    case critical = "critical"

    public var sfSymbol: String {
        switch self {
        case .healthy: return "checkmark.shield.fill"
        case .moderate: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }
}

/// Comprehensive capacity and depletion rate report for a backup destination volume.
public struct StorageForecastReport: Sendable, Equatable {
    public let profileId: UUID
    public let destinationURL: URL
    public let totalCapacityBytes: Int64
    public let freeSpaceBytes: Int64
    public let usedSpaceBytes: Int64
    public let usedPercentage: Double

    /// Estimated average net daily growth in bytes.
    public let averageDailyGrowthBytes: Int64
    /// Projected number of days until the destination volume reaches 100% capacity.
    public let estimatedDaysUntilFull: Int?
    /// Projected calendar date when capacity will be exhausted.
    public let estimatedFullDate: Date?
    /// Calculated operational health status.
    public let healthStatus: ForecastHealthStatus
    /// Whether user-configured quota warning threshold has been breached.
    public let isQuotaExceeded: Bool

    public init(
        profileId: UUID,
        destinationURL: URL,
        totalCapacityBytes: Int64,
        freeSpaceBytes: Int64,
        averageDailyGrowthBytes: Int64,
        estimatedDaysUntilFull: Int?,
        estimatedFullDate: Date?,
        healthStatus: ForecastHealthStatus,
        isQuotaExceeded: Bool
    ) {
        self.profileId = profileId
        self.destinationURL = destinationURL
        self.totalCapacityBytes = max(1, totalCapacityBytes)
        self.freeSpaceBytes = max(0, freeSpaceBytes)
        self.usedSpaceBytes = max(0, totalCapacityBytes - freeSpaceBytes)
        self.usedPercentage = min(1.0, max(0.0, Double(self.usedSpaceBytes) / Double(self.totalCapacityBytes)))
        self.averageDailyGrowthBytes = averageDailyGrowthBytes
        self.estimatedDaysUntilFull = estimatedDaysUntilFull
        self.estimatedFullDate = estimatedFullDate
        self.healthStatus = healthStatus
        self.isQuotaExceeded = isQuotaExceeded
    }

    /// Formatted daily growth string (e.g. "+1.4 GB / nap").
    public var formattedDailyGrowth: String {
        if averageDailyGrowthBytes <= 0 {
            return "0 B / " + L10n.t(.unitDay)
        }
        let formatted = ByteCountFormatter.string(fromByteCount: averageDailyGrowthBytes, countStyle: .file)
        return "+\(formatted) / " + L10n.t(.unitDay)
    }

    /// Formatted days until full display text.
    public var formattedDepletionText: String {
        guard let days = estimatedDaysUntilFull else {
            return L10n.t(.forecastSufficientSpace)
        }
        if days <= 0 {
            return L10n.t(.forecastDiskFullNow)
        }
        return String(format: L10n.t(.forecastDaysRemainingFormat), days)
    }
}

/// Actor calculating statistical trends and storage capacity forecasts based on snapshot manifests.
public actor StorageForecastEngine {
    public static let shared = StorageForecastEngine()

    public init() {}

    /// Evaluates current disk capacity and historical growth rates to project volume depletion.
    public func evaluateForecast(
        profile: BackupProfile,
        snapshots: [SnapshotRecord]
    ) async throws -> StorageForecastReport {
        let destURL = profile.destinationURL.standardizedFileURL

        // 1. Read real filesystem volume capacity
        var totalBytes: Int64 = 500 * 1024 * 1024 * 1024 // Default 500GB fallback
        var freeBytes: Int64 = 200 * 1024 * 1024 * 1024  // Default 200GB fallback

        if let values = try? destURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]) {
            if let tot = values.volumeTotalCapacity {
                totalBytes = Int64(tot)
            }
            if let availImportant = values.volumeAvailableCapacityForImportantUsage {
                freeBytes = availImportant
            } else if let avail = values.volumeAvailableCapacity {
                freeBytes = Int64(avail)
            }
        }


        // 2. Historical snapshots supplied by the caller (already sorted ascending by timestamp)
        let snapshots = snapshots.sorted { $0.timestamp < $1.timestamp }


        var dailyGrowth: Int64 = 0
        var daysUntilFull: Int? = nil
        var fullDate: Date? = nil

        if snapshots.count >= 2 {
            // Calculate growth rate across available historical window
            let oldest = snapshots.first!
            let newest = snapshots.last!

            let timeInterval = newest.timestamp.timeIntervalSince(oldest.timestamp)
            let elapsedDays = max(1.0, timeInterval / 86400.0)
            let sizeDifference = max(0, newest.totalBytes - oldest.totalBytes)

            let growthPerDay = Int64(Double(sizeDifference) / elapsedDays)
            dailyGrowth = max(0, growthPerDay)

            if dailyGrowth > 0 {
                let days = Double(freeBytes) / Double(dailyGrowth)
                let boundedDays = min(9999, max(0, Int(days)))
                daysUntilFull = boundedDays
                fullDate = Date().addingTimeInterval(TimeInterval(boundedDays * 86400))
            }
        } else if let single = snapshots.first {
            // With only 1 snapshot, assume modest daily growth of 5% of snapshot size
            let estimatedDaily = max(100 * 1024 * 1024, Int64(Double(single.totalBytes) * 0.05))
            dailyGrowth = estimatedDaily
            let days = Double(freeBytes) / Double(estimatedDaily)
            let boundedDays = min(9999, max(0, Int(days)))
            daysUntilFull = boundedDays
            fullDate = Date().addingTimeInterval(TimeInterval(boundedDays * 86400))
        }

        // 3. Quota evaluation
        let quotaThresholdBytes: Int64
        if let userGB = profile.quotaWarningThresholdGB {
            quotaThresholdBytes = Int64(userGB) * 1024 * 1024 * 1024
        } else {
            quotaThresholdBytes = 20 * 1024 * 1024 * 1024 // Default 20GB
        }

        let isQuotaExceeded = profile.enableQuotaAlerts && (freeBytes <= quotaThresholdBytes)
        let freePercent = Double(freeBytes) / Double(totalBytes)

        // 4. Determine Health Status
        let status: ForecastHealthStatus
        if isQuotaExceeded || freePercent < 0.05 || (daysUntilFull != nil && daysUntilFull! < 7) {
            status = .critical
        } else if freePercent < 0.15 || (daysUntilFull != nil && daysUntilFull! < 30) {
            status = .warning
        } else if daysUntilFull != nil && daysUntilFull! < 60 {
            status = .moderate
        } else {
            status = .healthy
        }

        return StorageForecastReport(
            profileId: profile.id,
            destinationURL: destURL,
            totalCapacityBytes: totalBytes,
            freeSpaceBytes: freeBytes,
            averageDailyGrowthBytes: dailyGrowth,
            estimatedDaysUntilFull: daysUntilFull,
            estimatedFullDate: fullDate,
            healthStatus: status,
            isQuotaExceeded: isQuotaExceeded
        )
    }
}
