import Foundation
import OtterKeepStorage

extension BackupSessionCoordinator {
    /// Validates system power, battery level, and thermal limits before I/O operations commence.
    func checkPowerAndThermalGovernor(profile: BackupProfile) throws {
        let check = PowerAndThermalGovernor.shared.shouldPauseBackup(pauseOnBattery: profile.pauseOnBattery)
        if check.shouldPause {
            let reason = check.reason ?? "Power or thermal conditions warrant postponement."
            logger.warning("Backup postponed by Power & Thermal Governor: \(reason)")
            LogManager.shared.log("Backup postponed by Governor for profile '\(profile.name)': \(reason)", level: .warning, category: "Power")
            throw FileSystemError.unknown("Backup paused: \(reason)")
        }
    }

    /// Arms anti-ransomware canary decoy monitoring in the source root if enabled.
    func prepareCanaryTrap(profile: BackupProfile) throws -> CanaryTrapMonitor? {
        guard profile.enableCanaryTraps else { return nil }

        let monitor = CanaryTrapMonitor { [weak self] error in
            self?.logger.error("🚨 CANARY TRIPWIRE DETECTED: \(error.description)")
            LogManager.shared.log("🚨 CANARY TRIPWIRE DETECTED for profile '\(profile.name)': \(error.reason)", level: .error, category: "Security")
            NotificationDeliveryService.shared.notifyRansomwareAlert(
                profileName: profile.name,
                reason: "Canary decoy tampering detected: \(error.reason)"
            )
        }

        // Ensure at least one decoy token is planted in source directory
        let hasCanary = (try? FileManager.default.contentsOfDirectory(atPath: profile.sourceURL.path(percentEncoded: false)))?
            .contains(where: { $0.hasPrefix(CanaryTrapMonitor.canaryPrefix) }) ?? false

        if !hasCanary {
            _ = try? monitor.plantCanary(in: profile.sourceURL)
            logger.info("Planted new canary decoy file in \(profile.sourceURL.path)")
        }

        monitor.arm(in: profile.sourceURL)
        return monitor
    }

    /// Manages mounting of encrypted APFS Sparsebundle containers when local encryption is enabled.
    func prepareEncryptedContainer(
        profile: BackupProfile,
        baseDestinationURL: URL
    ) throws -> (effectiveURL: URL, container: SparsebundleContainer?, containerFileURL: URL?) {
        guard let enc = profile.encryptionConfig, enc.isEnabled else {
            return (baseDestinationURL, nil, nil)
        }

        let container = SparsebundleContainer()
        let containerName = enc.containerName.isEmpty ? "OtterKeepSanctuary" : enc.containerName
        let containerFileURL = baseDestinationURL.appendingPathComponent("\(containerName).sparsebundle")
        let passphrase = enc.keychainKeyIdentifier ?? "OtterKeepVaultPassword"

        // Create container if it does not already exist
        if !FileManager.default.fileExists(atPath: containerFileURL.path(percentEncoded: false)) {
            logger.info("Creating new AES-256 encrypted APFS sparsebundle at \(containerFileURL.path)")
            LogManager.shared.log("Creating new AES-256 encrypted APFS sparsebundle for profile '\(profile.name)'", level: .info, category: "Security")
            try container.create(at: containerFileURL, volumeName: containerName, sizeGB: 2000, passphrase: passphrase)
        }

        // Attach the encrypted container
        logger.info("Mounting encrypted APFS sparsebundle...")
        let mountedURL = try container.attach(at: containerFileURL, passphrase: passphrase)
        logger.info("Encrypted sparsebundle mounted at \(mountedURL.path)")
        LogManager.shared.log("Encrypted sparsebundle mounted successfully at \(mountedURL.path)", level: .info, category: "Security")

        return (mountedURL, container, containerFileURL)
    }

    /// Safely detaches the mounted sparsebundle container upon session conclusion.
    func cleanupEncryptedContainer(
        container: SparsebundleContainer?,
        mountPoint: URL?
    ) {
        guard let container = container, let mountPoint = mountPoint else { return }
        logger.info("Detaching encrypted sparsebundle container at \(mountPoint.path)...")
        try? container.detach(mountPoint: mountPoint)
    }
}
