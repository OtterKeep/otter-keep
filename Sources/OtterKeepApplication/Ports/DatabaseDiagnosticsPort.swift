import Foundation

/// Port exposing central catalog database diagnostics and self-healing maintenance.
public protocol DatabaseDiagnosticsProviding: Sendable {
    /// Absolute filesystem path of the central catalog database.
    var databasePath: String { get }

    /// Runs integrity checks and repairs recoverable catalog inconsistencies.
    func performSelfHealingMaintenance() throws
}
