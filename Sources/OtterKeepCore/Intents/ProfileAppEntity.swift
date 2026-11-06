import AppIntents
import Foundation
import OtterKeepDomain

/// Represents an OtterKeep backup profile for Shortcuts, Siri, and AppIntents parameter selection.
public struct ProfileAppEntity: AppEntity, Sendable {
    public static let defaultQuery = ProfileEntityQuery()
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Backup Profile"

    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Dynamic resolver and suggestion query for configured backup profiles in Shortcuts.
public struct ProfileEntityQuery: EntityQuery, Sendable {
    public init() {}

    public func entities(for identifiers: [String]) async throws -> [ProfileAppEntity] {
        let profiles = ProfileStore.shared.loadProfiles()
        return profiles
            .filter { identifiers.contains($0.id.uuidString) }
            .map { ProfileAppEntity(id: $0.id.uuidString, name: $0.name) }
    }

    public func suggestedEntities() async throws -> [ProfileAppEntity] {
        let profiles = ProfileStore.shared.loadProfiles()
        return profiles.map { ProfileAppEntity(id: $0.id.uuidString, name: $0.name) }
    }
}
