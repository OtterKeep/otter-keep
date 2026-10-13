import Foundation
import OtterKeepDomain

/// Data Transfer Object representing a decoupled backup profile configuration for external layers.
public struct ProfileConfigurationDTO: Sendable, Codable, Equatable, Identifiable {
    public let id: UUID
    public let name: String
    public let sourcePath: String
    public let destinationPath: String
    public let excludePatterns: [String]
    public let isImmutabilityLockEnabled: Bool
    public let immutabilityLockDays: Int

    public init(
        id: UUID = UUID(),
        name: String,
        sourcePath: String,
        destinationPath: String,
        excludePatterns: [String] = [],
        isImmutabilityLockEnabled: Bool = true,
        immutabilityLockDays: Int = 30
    ) {
        self.id = id
        self.name = name
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.excludePatterns = excludePatterns
        self.isImmutabilityLockEnabled = isImmutabilityLockEnabled
        self.immutabilityLockDays = immutabilityLockDays
    }
}
