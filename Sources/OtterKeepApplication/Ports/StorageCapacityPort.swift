import Foundation
import OtterKeepDomain

/// Port exposing volume capacity metrics to the presentation layer.
public protocol StorageCapacityProviding: Sendable {
    /// Returns total, free, and available byte counts for the volume hosting the given URL.
    func storageCapacity(at url: URL) throws -> StorageCapacity
}
