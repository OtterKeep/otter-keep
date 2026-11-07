import Foundation
import Network
import OtterKeepApplication

/// Network reachability and constraint status analyzer.
public final class NetworkReachability: NetworkStatusProviding, @unchecked Sendable {
    public static let shared = NetworkReachability()

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.otterkeep.networkreachability")
    private let lock = NSLock()
    private var currentPath: NWPath?
    private let initialPathSemaphore = DispatchSemaphore(value: 0)
    private var hasReceivedInitialPath = false

    public init() {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            self.lock.lock()
            let isFirst = !self.hasReceivedInitialPath
            self.currentPath = path
            self.hasReceivedInitialPath = true
            self.lock.unlock()
            if isFirst {
                self.initialPathSemaphore.signal()
            }
        }
        self.monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    /// Waits briefly for NWPathMonitor to deliver its initial network state if not yet available.
    public func ensureInitialPath(timeout: TimeInterval = 1.0) {
        lock.lock()
        let received = hasReceivedInitialPath
        lock.unlock()
        if !received {
            _ = initialPathSemaphore.wait(timeout: .now() + timeout)
        }
    }

    /// True if any network connection is active.
    public var isConnected: Bool {
        ensureInitialPath(timeout: 0.5)
        lock.lock()
        defer { lock.unlock() }
        guard let path = currentPath else {
            // If path monitor hasn't delivered yet, fallback to true if local loopback or interfaces exist
            return true
        }
        return path.status == .satisfied
    }

    /// True if the current network connection is marked as expensive (e.g. cellular, mobile hotspot).
    public var isExpensive: Bool {
        ensureInitialPath(timeout: 0.5)
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.isExpensive ?? false
    }

    /// True if the system is currently in Low Data Mode.
    public var isConstrained: Bool {
        ensureInitialPath(timeout: 0.5)
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.isConstrained ?? false
    }

    /// Primary interface type.
    public var usesWiFiOrEthernet: Bool {
        ensureInitialPath(timeout: 0.5)
        lock.lock()
        defer { lock.unlock() }
        guard let path = currentPath else { return true }
        return path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
    }

    /// Evaluates whether the current network satisfies a given network constraint policy.
    public func satisfiesPolicy(unmeteredOnly: Bool) -> Bool {
        ensureInitialPath(timeout: 0.5)
        guard isConnected else { return false }
        if unmeteredOnly && (isExpensive || isConstrained) {
            return false
        }
        return true
    }

    private var cachedSSID: String? = nil
    private var lastSSIDLookup: Date = .distantPast

    /// Resolves the currently connected Wi-Fi network SSID (if any).
    /// Uses cached results for up to 5 seconds to prevent subprocess thrashing.
    public var currentWiFiSSID: String? {
        lock.lock()
        let now = Date()
        if now.timeIntervalSince(lastSSIDLookup) < 5.0 {
            let res = cachedSSID
            lock.unlock()
            return res
        }
        lock.unlock()

        let discovered = resolveCurrentSSID()
        lock.lock()
        self.cachedSSID = discovered
        self.lastSSIDLookup = now
        lock.unlock()
        return discovered
    }

    /// Internal helper executing lightweight networksetup query to read the current Wi-Fi SSID.
    private func resolveCurrentSSID() -> String? {
        // Try common interfaces en0 and en1
        for iface in ["en0", "en1"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
            task.arguments = ["-getairportnetwork", iface]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice

            do {
                try task.run()
                task.waitUntilExit()
                if task.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                        // Format: "Current Wi-Fi Network: MyNetwork"
                        if let range = output.range(of: "Current Wi-Fi Network: ") {
                            let ssid = String(output[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if !ssid.isEmpty {
                                return ssid
                            }
                        }
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    /// Validates whether replication or network backup is permitted given SSID rules and metered settings.
    public static func evaluatePolicy(
        currentSSID: String?,
        isMetered: Bool,
        isConnected: Bool = true,
        allowedSSIDs: [String] = [],
        disallowedSSIDs: [String] = [],
        pauseOnMetered: Bool = true
    ) -> NetworkPolicyEvaluationResult {
        guard isConnected else {
            return NetworkPolicyEvaluationResult(allowed: false, reason: "No active network connection")
        }

        if pauseOnMetered && isMetered {
            return NetworkPolicyEvaluationResult(allowed: false, reason: "Network is marked as metered or expensive (Personal Hotspot / Low Data Mode)")
        }

        // 1. Check disallowed list
        if let current = currentSSID, !current.isEmpty {
            let isBlocked = disallowedSSIDs.contains { $0.caseInsensitiveCompare(current) == .orderedSame }
            if isBlocked {
                return NetworkPolicyEvaluationResult(allowed: false, reason: "Current Wi-Fi '\(current)' is in the disallowed networks list")
            }
        }

        // 2. Check allowed list (if configured)
        if !allowedSSIDs.isEmpty {
            guard let current = currentSSID, !current.isEmpty else {
                return NetworkPolicyEvaluationResult(allowed: false, reason: "Not connected to any Wi-Fi network, but allowed SSIDs are required")
            }
            let isAllowed = allowedSSIDs.contains { $0.caseInsensitiveCompare(current) == .orderedSame }
            if !isAllowed {
                return NetworkPolicyEvaluationResult(allowed: false, reason: "Current Wi-Fi '\(current)' is not in the allowed networks list (\(allowedSSIDs.joined(separator: ", ")))")
            }
        }

        return NetworkPolicyEvaluationResult(allowed: true, reason: nil)
    }

    /// Validates whether replication or network backup is permitted given SSID rules and metered settings.
    public func evaluatePolicy(
        currentSSID: String? = nil,
        isMetered: Bool? = nil,
        allowedSSIDs: [String] = [],
        disallowedSSIDs: [String] = [],
        pauseOnMetered: Bool = true
    ) -> NetworkPolicyEvaluationResult {
        ensureInitialPath(timeout: 0.5)
        let effectiveSSID = currentSSID ?? self.currentWiFiSSID
        let effectiveMetered = isMetered ?? (self.isExpensive || self.isConstrained)
        return Self.evaluatePolicy(
            currentSSID: effectiveSSID,
            isMetered: effectiveMetered,
            isConnected: self.isConnected,
            allowedSSIDs: allowedSSIDs,
            disallowedSSIDs: disallowedSSIDs,
            pauseOnMetered: pauseOnMetered
        )
    }
}

/// Represents the evaluation result of a network constraint policy.
public struct NetworkPolicyEvaluationResult: Sendable {
    public let allowed: Bool
    public let reason: String?

    public var isPermitted: Bool { allowed }

    public init(allowed: Bool, reason: String? = nil) {
        self.allowed = allowed
        self.reason = reason
    }
}

