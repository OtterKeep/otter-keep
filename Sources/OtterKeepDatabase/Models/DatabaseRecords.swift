import Foundation
import SQLite3
import os
@_exported import OtterKeepDomain

/// Structured errors encountered during SQLite catalog database operations.
public enum DatabaseError: Error, Sendable, LocalizedError {
    /// Failed to open or initialize the SQLite database connection.
    case openFailed(String)
    /// SQL statement execution failed.
    case executionFailed(String, String)
    /// SQL query compilation/preparation failed.
    case prepareFailed(String, String)
    /// SQL statement step iteration failed.
    case stepFailed(String, String)

    /// Human-readable localized error description.
    public var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "Database connection error: \(msg)"
        case .executionFailed(let query, let msg): return "SQL execution error '\(query)': \(msg)"
        case .prepareFailed(let query, let msg): return "SQL prepare error '\(query)': \(msg)"
        case .stepFailed(let query, let msg): return "SQL step error '\(query)': \(msg)"
        }
    }
}
