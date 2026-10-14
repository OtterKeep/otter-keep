import Foundation
import IOKit.ps
import IOKit.pwr_mgt

/// Intelligent power, battery, and thermal governor ensuring non-disruptive, energy-aware background operations.
public final class PowerAndThermalGovernor: @unchecked Sendable {
    public static let shared = PowerAndThermalGovernor()

    /// Battery and power status snapshot.
    public struct PowerStatus: Sendable, Equatable {
        public let isOnBattery: Bool
        public let batteryPercentage: Int?
        public let isLowPowerMode: Bool
        public let thermalState: ProcessInfo.ThermalState
    }

    private let lock = NSLock()

    public init() {}

    /// Inspects the current system power, battery, and thermal environment.
    public func currentStatus() -> PowerStatus {
        let thermal = ProcessInfo.processInfo.thermalState
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

        var onBattery = false
        var batteryPercent: Int? = nil

        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] {
            for source in sources {
                if let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
                    if let powerSourceState = desc[kIOPSPowerSourceStateKey as String] as? String {
                        if powerSourceState == (kIOPSBatteryPowerValue as String) {
                            onBattery = true
                        }
                    }
                    if let currentCap = desc[kIOPSCurrentCapacityKey as String] as? Int,
                       let maxCap = desc[kIOPSMaxCapacityKey as String] as? Int,
                       maxCap > 0 {
                        batteryPercent = Int((Double(currentCap) / Double(maxCap)) * 100.0)
                    }
                }
            }
        }

        return PowerStatus(
            isOnBattery: onBattery,
            batteryPercentage: batteryPercent,
            isLowPowerMode: lowPower,
            thermalState: thermal
        )
    }

    /// Determines whether an ongoing or upcoming backup cycle should be paused or postponed.
    /// - Parameters:
    ///   - pauseOnBattery: Whether the user profile requests pausing while on battery.
    ///   - minimumBatteryThreshold: Minimum allowable battery percentage (defaults to 20%).
    /// - Returns: Tuple indicating whether to pause and an explanatory diagnostic reason.
    public func shouldPauseBackup(
        pauseOnBattery: Bool,
        minimumBatteryThreshold: Int = 20
    ) -> (shouldPause: Bool, reason: String?) {
        let status = currentStatus()

        // Critical thermal pressure immediately warrants a pause
        if status.thermalState == .critical {
            return (true, "macOS thermal state is critical (overheating risk)")
        }

        // Running on battery with battery pause policy
        if pauseOnBattery && status.isOnBattery {
            return (true, "Profile configured to pause backups on battery power")
        }

        // Low battery emergency guard (<20% or Low Power Mode active on battery)
        if status.isOnBattery {
            if let percent = status.batteryPercentage, percent < minimumBatteryThreshold {
                return (true, "Battery charge is critically low (\(percent)% < \(minimumBatteryThreshold)%)")
            }
            if status.isLowPowerMode {
                return (true, "macOS Low Power Mode is actively engaged on battery")
            }
        }

        return (false, nil)
    }

    /// Recommends concurrent worker count adjusted for current thermal strain.
    /// - Parameters:
    ///   - baseConcurrency: Baseline desired worker concurrency (e.g. 4 or 8).
    ///   - throttleOnThermal: Whether thermal throttling is enabled.
    /// - Returns: Dynamically adjusted concurrency limit.
    public func recommendedConcurrency(
        baseConcurrency: Int,
        throttleOnThermal: Bool
    ) -> Int {
        guard throttleOnThermal else { return max(1, baseConcurrency) }
        let thermal = ProcessInfo.processInfo.thermalState

        switch thermal {
        case .nominal:
            return max(1, baseConcurrency)
        case .fair:
            return max(1, Int(Double(baseConcurrency) * 0.75))
        case .serious:
            return 1 // Single threaded gentle execution
        case .critical:
            return 1
        @unknown default:
            return max(1, baseConcurrency)
        }
    }

    /// Provides micro-sleep pacing delay in nanoseconds to inject between I/O writes when throttled.
    /// - Parameter throttleOnThermal: Whether thermal throttling is enabled.
    /// - Returns: Delay in nanoseconds (0 if nominal).
    public func throttleDelayNanoseconds(throttleOnThermal: Bool) -> UInt64 {
        guard throttleOnThermal else { return 0 }
        let thermal = ProcessInfo.processInfo.thermalState

        switch thermal {
        case .nominal:
            return 0
        case .fair:
            return 500_000 // 0.5 ms
        case .serious:
            return 5_000_000 // 5 ms
        case .critical:
            return 25_000_000 // 25 ms
        @unknown default:
            return 0
        }
    }
}
