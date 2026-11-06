import Foundation
import OtterKeepApplication
import OtterKeepDatabase
import OtterKeepDomain
import OtterKeepStorage

/// Composition root owning the concrete storage and database engines and vending
/// Core-level coordinators, so that outer layers (UI, CLI) never depend on
/// `OtterKeepStorage` or `OtterKeepDatabase` types directly.
public final class EngineContainer: Sendable {
    private let storage: FileSystemProvider
    private let database: DatabaseEngine
    private let retentionManager: RetentionManager
    private let restoreEngine: RestoreEngine
    private let photosCoordinator: PhotosBackupCoordinator
    private let remoteProbe: RemoteDestinationProbing
    private let networkStatus: NetworkStatusProviding
    private let databaseDiagnostics: DatabaseDiagnosticsProviding

    /// Creates the container with the default production engine implementations.
    public init() {
        let storage = DefaultFileSystemProvider()
        let database = DatabaseEngine()
        let retentionManager = RetentionManager(storage: storage, database: database)
        self.storage = storage
        self.database = database
        self.retentionManager = retentionManager
        self.restoreEngine = RestoreEngine(storage: storage, database: database)
        self.photosCoordinator = PhotosBackupCoordinator(storage: storage, dbEngine: database)
        self.remoteProbe = RemoteDestinationProbe()
        self.networkStatus = NetworkReachability.shared
        self.databaseDiagnostics = CentralDatabase.shared
    }

    /// Creates an isolated backup session coordinator with its own SQLite connection,
    /// enabling zero-contention parallel backups.
    public func makeBackupSessionCoordinator() -> BackupSessionCoordinator {
        let sessionDb = DatabaseEngine()
        let sessionRetention = RetentionManager(storage: storage, database: sessionDb)
        return BackupSessionCoordinator(
            storage: storage,
            database: sessionDb,
            retentionManager: sessionRetention,
            volumeEjector: SystemVolumeEjector()
        )
    }

    /// Creates a coordinator for 3-2-1 remote replication jobs.
    public func makeReplicationCoordinator() -> BackupCopyJobCoordinator {
        BackupCopyJobCoordinator(storage: storage, database: database)
    }

    /// Engine performing file and snapshot restores.
    public var restore: RestoreEngine { restoreEngine }

    /// Coordinator driving Photos library backups.
    public var photos: PhotosBackupCoordinator { photosCoordinator }

    /// Manager applying Grandfather-Father-Son retention policies.
    public var retention: RetentionManager { retentionManager }

    /// Port probing remote storage destinations for reachability and credentials.
    public var remoteDestinationProbe: RemoteDestinationProbing { remoteProbe }

    /// Port reporting current network reachability and Wi-Fi metadata.
    public var network: NetworkStatusProviding { networkStatus }

    /// Port exposing central catalog database diagnostics.
    public var diagnostics: DatabaseDiagnosticsProviding { databaseDiagnostics }

    /// Queries total, free, and available capacity of the volume hosting the given URL.
    /// - Parameter url: A filesystem URL on the target volume.
    /// - Returns: The volume's `StorageCapacity`, or `nil` when it cannot be determined.
    public func storageCapacity(at url: URL) -> StorageCapacity? {
        try? storage.storageCapacity(at: url)
    }
}
