import Foundation

/// Read-only network status port exposing reachability and metering constraints to the presentation layer.
public protocol NetworkStatusProviding: Sendable {
    /// Indicates whether an active network path is currently available.
    var isConnected: Bool { get }

    /// Indicates whether the active network path is metered or expensive (e.g. cellular hotspot).
    var isExpensive: Bool { get }

    /// Indicates whether the active network path is in Low Data Mode.
    var isConstrained: Bool { get }

    /// The SSID of the currently joined Wi-Fi network, or `nil` when unavailable.
    var currentWiFiSSID: String? { get }
}
