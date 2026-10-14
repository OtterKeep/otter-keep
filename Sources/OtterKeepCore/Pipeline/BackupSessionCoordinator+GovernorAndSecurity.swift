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
            NotificationDeliveryService.shared.notifyGovernorPaused(profileName: profile.name, reason: reason)
            throw FileSystemError.unknown("Backup paused: \(reason)")
        }
    }

    /// Arms anti-ransomware canary decoy monitoring in the source root if enabled.
    func prepareCanaryTrap(profile: BackupProfile) throws -> CanaryTrapMonitor? {
        guard profile.enableCanaryTraps else { return nil }

        let monitor = CanaryTrapMonitor { [weak self] error in
            self?.logger.error("🚨 CANARY TRIPWIRE DETECTED: \(error.description)")
            LogManager.shared.log("🚨 CANARY TRIPWIRE DETECTED for profile '\(profile.name)': \(error.reason)", level: .error, category: "Security")
            
            // Immediate lockdown: set uchg immutability flag on target backup destination
            CanaryTrapMonitor.lockImmutably(at: profile.destinationURL)
            
            NotificationDeliveryService.shared.notifyRansomwareAlert(
                profileName: profile.name,
                reason: "Canary decoy tampering detected: \(error.reason)"
            )
        }

        // Ensure seductive decoy tokens are planted in source directory and registered in database
        let sourcePath = profile.sourceURL.path(percentEncoded: false)
        let hasCanary = (try? FileManager.default.contentsOfDirectory(atPath: sourcePath))?
            .contains(where: { CanaryTrapMonitor.attractiveDecoyNames.contains($0) || $0.hasPrefix(CanaryTrapMonitor.canaryPrefix) }) ?? false

        if !hasCanary {
            try? monitor.plantAttractiveDecoys(in: profile.sourceURL, profileId: profile.id)
            logger.info("Planted new attractive canary decoy tokens in \(profile.sourceURL.path)")
        }

        monitor.arm(in: profile.sourceURL, profileId: profile.id)
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
        
        // Retrieve passphrase from secure macOS Keychain
        let account = "sparsebundle_\(profile.id.uuidString)"
        let passphrase: String
        if let stored = KeychainManager.getSecret(for: account) {
            passphrase = stored
        } else if let customKey = enc.keychainKeyIdentifier, let storedCustom = KeychainManager.getSecret(for: customKey) {
            passphrase = storedCustom
        } else {
            // Auto-provision secure master key in Keychain if missing
            let generatedKey = UUID().uuidString + "-" + UUID().uuidString
            try? KeychainManager.saveSecret(generatedKey, for: account)
            passphrase = generatedKey
        }

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
