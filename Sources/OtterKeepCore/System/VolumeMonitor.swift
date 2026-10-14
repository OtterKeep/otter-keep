import Foundation
import Darwin
import OtterKeepStorage

/// Categorized Copy-on-Write operational modes based on source and destination volume capabilities.
public enum CoWMode: Sendable, Equatable {
    /// Zero-copy instantaneous APFS clone within the same APFS volume.
    case intraVolumeCoW
    /// Incremental backup to an external APFS drive with target-side deduplicated cloning.
    case targetSideSnapshotCoW
    /// Physical fallback stream copying to exFAT external drives.
    case exFATFallback
    /// Read-only NTFS volume (macOS native driver, usable only as backup source).
    case ntfsReadOnly
    /// Writable NTFS volume via 3rd party driver (e.g. Paragon, Tuxera).
    case ntfsReadWrite
    /// Standard fallback copying to other non-APFS drives (FAT, SMB, NFS, network shares).
    case nonAPFS

    /// UI badge localization key.
    public var badgeKey: L10n.Key {
        switch self {
        case .intraVolumeCoW: return .cowBadgeIntraVolume
        case .targetSideSnapshotCoW: return .cowBadgeSnapshotTarget
        case .exFATFallback: return .cowBadgeExFAT
        case .ntfsReadOnly: return .cowBadgeNTFSReadOnly
        case .ntfsReadWrite: return .cowBadgeNTFS
        case .nonAPFS: return .cowBadgeNonAPFS
        }
    }

    /// UI description localization key.
    public var descriptionKey: L10n.Key {
        switch self {
        case .intraVolumeCoW: return .cowDescIntraVolume
        case .targetSideSnapshotCoW: return .cowDescSnapshotTarget
        case .exFATFallback: return .cowDescExFAT
        case .ntfsReadOnly: return .cowDescNTFSReadOnly
        case .ntfsReadWrite: return .cowDescNTFS
        case .nonAPFS: return .cowDescNonAPFS
        }
    }
}

/// Evaluation summary describing source and destination volume filesystem relationships.
public struct VolumeEvaluationResult: Sendable, Equatable {
    /// True if source and destination reside on the exact same physical volume.
    public let isSameVolume: Bool
    /// True if destination volume is formatted as APFS.
    public let isTargetAPFS: Bool
    /// Filesystem type name string of destination.
    public let targetFSType: String
    /// Filesystem type name string of source.
    public let sourceFSType: String
    /// True if destination is mounted in read-only mode.
    public let isTargetReadOnly: Bool
    /// True if target is Microsoft exFAT.
    public var isTargetExFAT: Bool { targetFSType.lowercased() == "exfat" }
    /// True if target is Microsoft NTFS.
    public var isTargetNTFS: Bool { targetFSType.lowercased() == "ntfs" || targetFSType.lowercased().contains("ntfs") }
    /// True if source is Microsoft exFAT.
    public var isSourceExFAT: Bool { sourceFSType.lowercased() == "exfat" }
    /// True if source is Microsoft NTFS.
    public var isSourceNTFS: Bool { sourceFSType.lowercased() == "ntfs" || sourceFSType.lowercased().contains("ntfs") }
    /// Determined Copy-on-Write mode.
    public let cowMode: CoWMode

    /// Initializes a `VolumeEvaluationResult`.
    public init(
        isSameVolume: Bool,
        isTargetAPFS: Bool,
        targetFSType: String,
        sourceFSType: String = "unknown",
        isTargetReadOnly: Bool = false,
        cowMode: CoWMode
    ) {
        self.isSameVolume = isSameVolume
        self.isTargetAPFS = isTargetAPFS
        self.targetFSType = targetFSType
        self.sourceFSType = sourceFSType
        self.isTargetReadOnly = isTargetReadOnly
        self.cowMode = cowMode
    }
}

/// Evaluator analyzing volume capabilities via Darwin `statfs` filesystem identifiers.
public enum VolumeCapabilityEvaluator {
    /// Evaluates volume relationship and CoW capabilities between source and destination folders.
    /// - Parameters:
    ///   - sourceURL: Source directory URL.
    ///   - destinationURL: Destination directory URL.
    /// - Returns: A `VolumeEvaluationResult` categorization.
    public static func evaluate(sourceURL: URL, destinationURL: URL) -> VolumeEvaluationResult {
        var srcFs = statfs()
        var dstFs = statfs()

        let srcPath = sourceURL.standardizedFileURL.path(percentEncoded: false)
        let dstPath = destinationURL.standardizedFileURL.path(percentEncoded: false)

        let srcRes = statfs(srcPath, &srcFs)
        let dstRes = statfs(dstPath, &dstFs)

        var isSame = false
        var targetFSType = "unknown"
        var sourceFSType = "unknown"
        var isTargetAPFS = false
        var isTargetReadOnly = false

        if srcRes == 0 {
            sourceFSType = withUnsafePointer(to: &srcFs.f_fstypename) { ptr -> String in
                let rawPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                return String(cString: rawPtr)
            }
        }

        if dstRes == 0 {
            targetFSType = withUnsafePointer(to: &dstFs.f_fstypename) { ptr -> String in
                let rawPtr = UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                return String(cString: rawPtr)
            }
            isTargetAPFS = targetFSType.lowercased() == "apfs"
            isTargetReadOnly = (dstFs.f_flags & UInt32(MNT_RDONLY)) != 0
        }

        if srcRes == 0 && dstRes == 0 {
            // Compare fsid values to determine whether both paths share the identical volume
            isSame = (srcFs.f_fsid.val.0 == dstFs.f_fsid.val.0 && srcFs.f_fsid.val.1 == dstFs.f_fsid.val.1)
        }

        let targetTypeLower = targetFSType.lowercased()
        let mode: CoWMode
        if targetTypeLower == "exfat" {
            mode = .exFATFallback
        } else if targetTypeLower == "ntfs" || targetTypeLower.contains("ntfs") {
            mode = isTargetReadOnly ? .ntfsReadOnly : .ntfsReadWrite
        } else if !isTargetAPFS {
            mode = .nonAPFS
        } else if isSame {
            mode = .intraVolumeCoW
        } else {
            mode = .targetSideSnapshotCoW
        }

        return VolumeEvaluationResult(
            isSameVolume: isSame,
            isTargetAPFS: isTargetAPFS,
            targetFSType: targetFSType,
            sourceFSType: sourceFSType,
            isTargetReadOnly: isTargetReadOnly,
            cowMode: mode
        )
    }


    /// Checks whether a given path is currently accessible on the mounted filesystem.
    /// - Parameter url: Path URL.
    /// - Returns: True if file or directory exists.
    public static func isPathAccessible(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.standardizedFileURL.path(percentEncoded: false), isDirectory: &isDir)
    }
}

/// Zero-configuration adoption and drive rotation metadata stamped on external backup storage targets.
public struct DriveProfileMetadata: Codable, Sendable, Equatable {
    public static let fileName = ".otterkeep_profile_meta.json"

    public let profileId: UUID
    public let profileName: String
    public let createdAt: Date
    public let sanctuaryVersion: String

    public init(
        profileId: UUID,
        profileName: String,
        createdAt: Date = Date(),
        sanctuaryVersion: String = CoreEngine.version
    ) {
        self.profileId = profileId
        self.profileName = profileName
        self.createdAt = createdAt
        self.sanctuaryVersion = sanctuaryVersion
    }

    /// Writes profile metadata to the target destination folder.
    public static func write(for profile: BackupProfile, to destinationURL: URL) {
        let meta = DriveProfileMetadata(profileId: profile.id, profileName: profile.name)
        let fileURL = destinationURL.appendingPathComponent(fileName)
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Reads profile metadata from a given root or folder URL.
    public static func read(from folderURL: URL) -> DriveProfileMetadata? {
        let fileURL = folderURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)),
              let data = try? Data(contentsOf: fileURL),
              let meta = try? JSONDecoder().decode(DriveProfileMetadata.self, from: data) else {
            return nil
        }
        return meta
    }
}

/// Thread-safe monitor listening to macOS volume mount and unmount notifications.
public final class VolumeMonitor: @unchecked Sendable {
    /// Shared singleton instance.
    public static let shared = VolumeMonitor()

    /// Handler closure invoked when a volume mount change occurs.
    public typealias VolumeChangeHandler = @Sendable (_ mountedURL: URL?) -> Void

    /// Handler closure invoked when an automated backup trigger is requested for a profile.
    public typealias AutoBackupTriggerHandler = @Sendable (_ profile: BackupProfile) -> Void

    /// Handler closure invoked when an external volume with an unadopted profile is discovered.
    public typealias UnadoptedDriveHandler = @Sendable (_ metadata: DriveProfileMetadata, _ volumeURL: URL) -> Void

    private let lock = NSLock()
    private let observer: VolumeObserving
    private var handlers: [VolumeChangeHandler] = []
    private var autoBackupHandler: AutoBackupTriggerHandler?
    public var onUnadoptedDriveDetected: UnadoptedDriveHandler?
    private var lastTriggeredPerVolume: [String: Date] = [:]

    /// Creates a monitor driven by the given platform observer.
    /// - Parameter observer: Platform mount/unmount observer; defaults to the AppKit-backed observer.
    public init(observer: VolumeObserving = SystemVolumeObserver()) {
        self.observer = observer
        startListening()
    }

    deinit {
        stopListening()
    }

    /// Registers a volume change observer handler.
    /// - Parameter handler: Callback closure.
    public func addHandler(_ handler: @escaping VolumeChangeHandler) {
        lock.lock()
        defer { lock.unlock() }
        handlers.append(handler)
    }

    /// Sets the handler invoked when a profile should automatically start backup on volume mount.
    public func setAutoBackupHandler(_ handler: @escaping AutoBackupTriggerHandler) {
        lock.lock()
        defer { lock.unlock() }
        autoBackupHandler = handler
    }

    /// Evaluates whether a mounted volume corresponds to any profile's destination with mount trigger enabled.
    /// Supports direct path matches, registered multi-drive rotation volume UUIDs, and zero-config adoption tags.
    /// Enforces a cooldown (default: 15 minutes / 900 seconds) to prevent redundant runs.
    public func evaluateMountForAutoBackup(
        mountedURL: URL,
        profiles: [BackupProfile],
        cooldownSeconds: TimeInterval = 900
    ) -> [BackupProfile] {
        lock.lock()
        defer { lock.unlock() }

        let mountedPath = BackupProfile.canonicalizePath(mountedURL.standardizedFileURL.path(percentEncoded: false))
        var triggeredProfiles: [BackupProfile] = []
        let now = Date()

        // Extract volume UUID if available
        let volumeUUID = (try? mountedURL.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString

        // Check for zero-config adoption tag at root of mounted drive
        let rootMeta = DriveProfileMetadata.read(from: mountedURL)

        for profile in profiles where profile.backupOnVolumeMount {
            let destPath = BackupProfile.canonicalizePath(profile.destinationURL.standardizedFileURL.path(percentEncoded: false))
            let pathMatches = destPath == mountedPath || destPath.hasPrefix(mountedPath + "/")

            // Check multi-drive rotation UUID match
            let uuidMatches = volumeUUID != nil && profile.destinationVolumeUUIDs.contains(volumeUUID!)

            // Check zero-config adoption tag match
            let metaMatches = rootMeta?.profileId == profile.id

            if pathMatches || uuidMatches || metaMatches {
                let cacheKey = "\(profile.id.uuidString)_\(mountedPath)"
                if let lastDate = lastTriggeredPerVolume[cacheKey], now.timeIntervalSince(lastDate) < cooldownSeconds {
                    LogManager.shared.log("Skipping mount backup trigger for '\(profile.name)': Cooldown active (\(Int(now.timeIntervalSince(lastDate)))s elapsed).", level: .debug, category: "Storage")
                    continue
                }
                lastTriggeredPerVolume[cacheKey] = now
                triggeredProfiles.append(profile)
            }
        }
        return triggeredProfiles
    }

    /// Evaluates and dispatches automated backups for profiles matching the mounted volume.
    public func handleMountedVolume(
        _ mountedURL: URL,
        profiles: [BackupProfile],
        cooldownSeconds: TimeInterval = 900
    ) {
        let matching = evaluateMountForAutoBackup(mountedURL: mountedURL, profiles: profiles, cooldownSeconds: cooldownSeconds)
        for profile in matching {
            LogManager.shared.log("Mounted volume '\(mountedURL.lastPathComponent)' matched profile '\(profile.name)'. Initiating automatic backup...", level: .info, category: "Storage")
            NotificationDeliveryService.shared.notifyVolumeMountTrigger(profileName: profile.name, volumeName: mountedURL.lastPathComponent)
            autoBackupHandler?(profile)
        }

        // Check for unadopted profile metadata tag
        if let rootMeta = DriveProfileMetadata.read(from: mountedURL) {
            let alreadyKnown = profiles.contains(where: { $0.id == rootMeta.profileId })
            if !alreadyKnown {
                LogManager.shared.log("Unadopted profile metadata found on '\(mountedURL.lastPathComponent)': '\(rootMeta.profileName)' [UUID: \(rootMeta.profileId.uuidString)].", level: .info, category: "Storage")
                onUnadoptedDriveDetected?(rootMeta, mountedURL)
            }
        }
    }

    private func notifyHandlers(with url: URL?) {
        lock.lock()
        let currentHandlers = handlers
        lock.unlock()

        for handler in currentHandlers {
            handler(url)
        }
    }

    private func startListening() {
        observer.startObserving(
            onMount: { [weak self] mountedURL in
                guard let self = self else { return }
                LogManager.shared.log("Volume mounted: \(mountedURL?.path ?? "unknown")", level: .info, category: "Storage")
                self.notifyHandlers(with: mountedURL)
            },
            onUnmount: { [weak self] unmountedURL in
                guard let self = self else { return }
                LogManager.shared.log("Volume unmounted: \(unmountedURL?.path ?? "unknown")", level: .warning, category: "Storage")
                self.notifyHandlers(with: nil)
            }
        )
    }

    private func stopListening() {
        observer.stopObserving()
    }
}
