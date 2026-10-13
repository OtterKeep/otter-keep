import Foundation
import OtterKeepDomain

/// Interactor / Use Case for querying historical snapshots through an abstract repository port.
public struct ListSnapshotsUseCase: Sendable {
    private let repository: SnapshotRepositoryProtocol

    public init(repository: SnapshotRepositoryProtocol) {
        self.repository = repository
    }

    public func execute() async throws -> [SnapshotRecord] {
        try await repository.listSnapshots()
    }

    /// Executes query returning standardized Data Transfer Objects (DTOs) for presentation and external layers.
    public func executeDTOs() async throws -> [SnapshotDTO] {
        let entities = try await repository.listSnapshots()
        return entities.map { SnapshotDTO(from: $0) }
    }
}

/// Interactor / Use Case for retrieving a specific snapshot and its indexed files.
public struct GetSnapshotDetailsUseCase: Sendable {
    private let snapshotRepository: SnapshotRepositoryProtocol
    private let fileRepository: FileCatalogRepositoryProtocol

    public init(snapshotRepository: SnapshotRepositoryProtocol, fileRepository: FileCatalogRepositoryProtocol) {
        self.snapshotRepository = snapshotRepository
        self.fileRepository = fileRepository
    }

    public struct Result: Sendable {
        public let snapshot: SnapshotRecord
        public let files: [FileCatalogRecord]

        public init(snapshot: SnapshotRecord, files: [FileCatalogRecord]) {
            self.snapshot = snapshot
            self.files = files
        }
    }

    public func execute(snapshotId: String) async throws -> Result? {
        guard let snapshot = try await snapshotRepository.getSnapshot(id: snapshotId) else {
            return nil
        }
        let files = try await fileRepository.listFiles(forSnapshotId: snapshotId)
        return Result(snapshot: snapshot, files: files)
    }

    /// Executes query returning a composite SnapshotDetailsDTO across layer boundaries.
    public func executeDTO(snapshotId: String) async throws -> SnapshotDetailsDTO? {
        guard let snapshot = try await snapshotRepository.getSnapshot(id: snapshotId) else {
            return nil
        }
        let files = try await fileRepository.listFiles(forSnapshotId: snapshotId)
        return SnapshotDetailsDTO(snapshot: snapshot, files: files)
    }
}

/// Interactor / Use Case for updating WORM immutability locks on snapshots.
public struct UpdateSnapshotLockUseCase: Sendable {
    private let snapshotRepository: SnapshotRepositoryProtocol
    private let fileSystem: FileSystemPort?

    public init(snapshotRepository: SnapshotRepositoryProtocol, fileSystem: FileSystemPort? = nil) {
        self.snapshotRepository = snapshotRepository
        self.fileSystem = fileSystem
    }

    public func execute(
        snapshotId: String,
        lockedUntil: Date?,
        snapshotRootURL: URL? = nil
    ) async throws {
        try await snapshotRepository.updateSnapshotLockedUntil(id: snapshotId, lockedUntil: lockedUntil)

        if let rootURL = snapshotRootURL, let fs = fileSystem {
            let isLockActive = (lockedUntil != nil && lockedUntil! > Date())
            try? fs.setImmutable(at: rootURL, immutable: isLockActive, recursive: true)
        }
    }
}
