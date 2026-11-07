import Foundation
import CryptoKit
import Darwin
import OtterKeepDatabase

/// Anti-ransomware canary trap coordinator that plants decoy files and monitors them for external tampering.
public final class CanaryTrapMonitor: @unchecked Sendable {
    public static let canaryPrefix = ".otterkeep_canary_"
    public static let canaryExtension = ".dat"

    /// Seductive decoy file names according to system specification
    public static let attractiveDecoyNames = [
        ".otterkeep_canary_financials.docx",
        ".otterkeep_canary_vault.pdf"
    ]

    /// Error thrown when a canary decoy file has been altered, encrypted, or destroyed.
    public struct CanaryTrapTriggeredError: Error, CustomStringConvertible, Sendable {
        public let canaryPath: String
        public let reason: String

        public var description: String {
            "Canary Trap Triggered at '\(canaryPath)': \(reason)"
        }
    }

    private struct CanaryRecord {
        let url: URL
        let expectedSHA256: String
        var dispatchSource: DispatchSourceFileSystemObject?
        var fileDescriptor: Int32?
    }

    private let lock = NSLock()
    private var records: [CanaryRecord] = []
    private var isArmed = false
    private let queue = DispatchQueue(label: "com.otterkeep.canarytrap", qos: .userInitiated)
    private let onTripwire: @Sendable (CanaryTrapTriggeredError) -> Void
    public var onEmergencyHalt: (@Sendable () -> Void)?

    /// Initializes a CanaryTrapMonitor.
    /// - Parameter onTripwire: Closure invoked immediately upon canary file tampering.
    public init(onTripwire: @escaping @Sendable (CanaryTrapTriggeredError) -> Void) {
        self.onTripwire = onTripwire
    }

    /// Plants a canary trap decoy file in the specified directory, optionally registering it in CentralDatabase.
    /// - Parameters:
    ///   - directoryURL: Target folder where the canary token should be deposited.
    ///   - profileId: Optional backup profile UUID.
    ///   - customName: Optional custom file name for the canary.
    /// - Returns: Planted canary file URL.
    @discardableResult
    public func plantCanary(in directoryURL: URL, profileId: UUID? = nil, customName: String? = nil) throws -> URL {
        let canaryName = customName ?? "\(Self.canaryPrefix)\(UUID().uuidString.prefix(8))\(Self.canaryExtension)"
        let fileURL = directoryURL.appendingPathComponent(canaryName)

        // Generate distinctive non-empty decoy content
        let decoyContent = "--- OTTERKEEP SANCTUARY CANARY DECOY TOKEN [\(UUID().uuidString)] ---\n"
        let data = decoyContent.data(using: .utf8) ?? Data()
        try data.write(to: fileURL, options: .atomic)

        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()

        if let pid = profileId {
            let record = CentralDatabase.CentralCanaryRecord(
                profileId: pid.uuidString,
                fileName: canaryName,
                expectedSHA256: hash
            )
            try? CentralDatabase.shared.saveCanaryRecord(record)
        }

        lock.lock()
        records.removeAll(where: { $0.url.path == fileURL.path })
        records.append(CanaryRecord(url: fileURL, expectedSHA256: hash, dispatchSource: nil, fileDescriptor: nil))
        lock.unlock()

        return fileURL
    }

    /// Plants all standard seductive decoy canaries in the specified directory.
    public func plantAttractiveDecoys(in directoryURL: URL, profileId: UUID) throws {
        for name in Self.attractiveDecoyNames {
            try plantCanary(in: directoryURL, profileId: profileId, customName: name)
        }
    }

    /// Scans a directory for existing canary files, loads authentic fingerprints from database, and arms monitoring.
    /// - Parameters:
    ///   - rootURL: Directory URL to search and arm.
    ///   - profileId: Optional profile UUID to verify against persisted signatures.
    public func arm(in rootURL: URL, profileId: UUID? = nil) {
        lock.lock()
        defer { lock.unlock() }

        guard !isArmed else { return }

        // If profileId is given, load known golden fingerprints from CentralDatabase
        var dbFingerprints: [String: String] = [:]
        if let pid = profileId {
            if let dbRecords = try? CentralDatabase.shared.loadCanaryRecords(profileId: pid.uuidString) {
                for r in dbRecords {
                    dbFingerprints[r.fileName] = r.expectedSHA256
                }
            }
        }

        // Discover any pre-existing canary files in the root folder
        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsSubdirectoryDescendants, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                let name = fileURL.lastPathComponent
                let isCanary = name.hasPrefix(Self.canaryPrefix) || Self.attractiveDecoyNames.contains(name)
                if isCanary {
                    if !records.contains(where: { $0.url.path == fileURL.path }) {
                        if let expected = dbFingerprints[name] {
                            // Check immediately against golden signature in database
                            if let data = try? Data(contentsOf: fileURL) {
                                let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                                if hash != expected {
                                    onEmergencyHalt?()
                                    onTripwire(CanaryTrapTriggeredError(canaryPath: fileURL.path, reason: "Pre-existing canary signature mismatch (tampered prior to arming)"))
                                }
                            }
                            records.append(CanaryRecord(url: fileURL, expectedSHA256: expected, dispatchSource: nil, fileDescriptor: nil))
                        } else if let data = try? Data(contentsOf: fileURL) {
                            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
                            records.append(CanaryRecord(url: fileURL, expectedSHA256: hash, dispatchSource: nil, fileDescriptor: nil))
                        }
                    }
                }
            }
        }

        // Arm dispatch sources on all registered canaries
        for i in 0..<records.count {
            let record = records[i]
            let fd = open(record.url.path(percentEncoded: false), O_EVTONLY)
            guard fd >= 0 else { continue }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.delete, .write, .extend, .attrib, .rename, .revoke],
                queue: queue
            )

            let canaryURL = record.url
            let expectedHash = record.expectedSHA256

            source.setEventHandler { [weak self] in
                guard let self = self else { return }
                self.verifyCanary(at: canaryURL, expectedHash: expectedHash)
            }

            source.setCancelHandler {
                close(fd)
            }

            source.resume()
            records[i].fileDescriptor = fd
            records[i].dispatchSource = source
        }

        isArmed = true
    }

    /// Disarms all active canary file monitors.
    public func disarm() {
        lock.lock()
        defer { lock.unlock() }

        guard isArmed else { return }

        for i in 0..<records.count {
            records[i].dispatchSource?.cancel()
            records[i].dispatchSource = nil
            records[i].fileDescriptor = nil
        }

        isArmed = false
    }

    /// Verifies the integrity of all monitored canary tokens synchronously.
    /// - Throws: `CanaryTrapTriggeredError` if any canary is corrupted or missing.
    public func verifyAll() throws {
        lock.lock()
        let currentRecords = records
        lock.unlock()

        for record in currentRecords {
            guard FileManager.default.fileExists(atPath: record.url.path(percentEncoded: false)) else {
                throw CanaryTrapTriggeredError(
                    canaryPath: record.url.path(percentEncoded: false),
                    reason: "Canary file was unexpectedly deleted or moved"
                )
            }

            guard let data = try? Data(contentsOf: record.url) else {
                throw CanaryTrapTriggeredError(
                    canaryPath: record.url.path(percentEncoded: false),
                    reason: "Unable to read canary file data"
                )
            }

            let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
            guard hash == record.expectedSHA256 else {
                throw CanaryTrapTriggeredError(
                    canaryPath: record.url.path(percentEncoded: false),
                    reason: "Canary file cryptographic signature mismatch (possible encryption/corruption)"
                )
            }
        }
    }

    /// Sets the macOS immutability flag (`uchg`) and read-only permissions (`0555`) to protect target from alteration.
    /// - Parameter url: Filesystem URL to lock immutably.
    public static func lockImmutably(at url: URL) {
        let path = url.path(percentEncoded: false)
        _ = chflags(path, UInt32(UF_IMMUTABLE))
        _ = chmod(path, 0o555)
    }

    /// Removes the macOS immutability flag (`uchg`) on a path.
    /// - Parameter url: Filesystem URL to unlock.
    public static func unlockImmutability(at url: URL) {
        let path = url.path(percentEncoded: false)
        _ = chflags(path, 0)
        _ = chmod(path, 0o755)
    }

    // MARK: - Internal Verification

    private func verifyCanary(at url: URL, expectedHash: String) {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            onEmergencyHalt?()
            let error = CanaryTrapTriggeredError(canaryPath: path, reason: "Canary token deleted or renamed in real-time")
            onTripwire(error)
            return
        }

        guard let data = try? Data(contentsOf: url) else {
            onEmergencyHalt?()
            let error = CanaryTrapTriggeredError(canaryPath: path, reason: "Canary token I/O read failure during modification")
            onTripwire(error)
            return
        }

        let hash = SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
        if hash != expectedHash {
            onEmergencyHalt?()
            let error = CanaryTrapTriggeredError(canaryPath: path, reason: "Canary token content modified/encrypted in real-time")
            onTripwire(error)
        }
    }

    deinit {
        disarm()
    }
}
