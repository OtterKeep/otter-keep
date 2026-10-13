import Foundation
import UserNotifications
import os

/// Service managing macOS system notifications (`UNUserNotificationCenter`) and proactive backup alerts.
public final class NotificationDeliveryService: NSObject, @unchecked Sendable, UNUserNotificationCenterDelegate {
    public static let shared = NotificationDeliveryService()
    private let presenter: NotificationPresenting
    private let logger = Logger(subsystem: "com.otterkeep", category: "Notifications")
    private let lock = NSLock()
    private var _onNotificationPosted: (@Sendable (String, String) -> Void)?

    /// Optional callback for notifications (used in headless CLI or automated tests).
    public var onNotificationPosted: (@Sendable (String, String) -> Void)? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _onNotificationPosted
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _onNotificationPosted = newValue
        }
    }

    private override init() {
        self.presenter = SystemNotificationPresenter()
        super.init()
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    private var isNotificationSupported: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    private func resolveNotificationAttachmentURL() -> URL? {
        presenter.notificationAttachmentIconURL()
    }

    private func attachApplicationIconIfAvailable(to content: UNMutableNotificationContent) {
        guard content.attachments.isEmpty else { return }
        if let iconURL = resolveNotificationAttachmentURL() {
            if let attachment = try? UNNotificationAttachment(identifier: "app_icon_\(UUID().uuidString.prefix(6))", url: iconURL, options: nil) {
                content.attachments = [attachment]
            }
        }
    }

    private func dispatchNotification(identifier: String, content: UNMutableNotificationContent) {
        onNotificationPosted?(content.title, content.body)

        // Attach application icon so the notification banner prominently shows the OtterKeep icon
        attachApplicationIconIfAvailable(to: content)

        guard isNotificationSupported else {
            logger.debug("Notifications skipped UNUserNotificationCenter (no bundle identifier): [\(content.title)] \(content.body)")
            presenter.deliverFallbackNotification(title: content.title, body: content.body)
            return
        }

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // immediate delivery
        )

        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let err = error {
                self?.logger.warning("Failed to deliver notification (\(identifier)): \(err.localizedDescription)")
            }
        }
    }

    /// Requests notification permissions from the user.
    public func requestAuthorization() async -> Bool {
        guard isNotificationSupported else {
            logger.debug("requestAuthorization skipped (no bundle identifier)")
            return true
        }
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization status: \(granted)")
            return granted
        } catch {
            logger.warning("Notification authorization error: \(error.localizedDescription)")
            return false
        }
    }

    /// Delivers a notification when a backup finishes successfully or with warnings.
    /// - Parameters:
    ///   - profileName: Name of the backup profile.
    ///   - status: Completion status.
    ///   - copiedCount: Count of copied files.
    ///   - durationSec: Elapsed seconds.
    public func notifyBackupCompleted(profileName: String, status: String, copiedCount: Int, durationSec: Double) {
        let content = UNMutableNotificationContent()
        content.title = String(format: L10n.t(.notifBackupCompletedTitleFormat), profileName)
        content.sound = .default

        if status == "completed" {
            content.body = String(format: L10n.t(.notifBackupCompletedSuccessFormat), copiedCount, durationSec)
        } else {
            content.body = String(format: L10n.t(.notifBackupCompletedWarningFormat), status)
        }

        dispatchNotification(identifier: "com.otterkeep.backup.completed.\(UUID().uuidString)", content: content)
    }

    /// Delivers an alert when a backup fails with an unrecoverable error.
    /// - Parameters:
    ///   - profileName: Name of the backup profile.
    ///   - errorMessage: Error message description.
    public func notifyBackupFailed(profileName: String, errorMessage: String) {
        let content = UNMutableNotificationContent()
        content.title = String(format: L10n.t(.notifBackupFailedTitleFormat), profileName)
        content.body = String(format: L10n.t(.notifBackupFailedBodyFormat), errorMessage)
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.backup.failed.\(UUID().uuidString)", content: content)
    }

    /// Delivers a Stale Backup Alert when an external destination drive has not been connected for days.
    /// - Parameters:
    ///   - profileName: Name of the backup profile.
    ///   - daysInactive: Days since last backup run.
    ///   - driveName: Target destination drive name.
    public func notifyStaleBackup(profileName: String, daysInactive: Int, driveName: String) {
        let content = UNMutableNotificationContent()
        content.title = String(format: L10n.t(.notifStaleBackupTitleFormat), profileName)
        content.body = String(format: L10n.t(.notifStaleBackupBodyFormat), driveName, daysInactive)
        content.sound = .default

        dispatchNotification(identifier: "com.otterkeep.stale.\(profileName)", content: content)
    }

    /// Delivers a critical alert when data scrubbing discovers bit-rot or file corruption.
    /// - Parameters:
    ///   - corruptedCount: Number of corrupt files detected.
    ///   - destinationName: Destination storage identifier.
    public func notifyBitRotDetected(corruptedCount: Int, destinationName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifBitRotTitle)
        content.body = String(format: L10n.t(.notifBitRotBodyFormat), corruptedCount, destinationName)
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.bitrot.\(UUID().uuidString)", content: content)
    }

    /// Delivers a critical alert when ransomware patterns or abnormal rate of change is detected.
    /// - Parameters:
    ///   - profileName: Name of the backup profile.
    ///   - reason: Anomaly detection rationale.
    public func notifyRansomwareAlert(profileName: String, reason: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifRansomwareAlertTitle)
        content.body = String(format: L10n.t(.notifRansomwareAlertBodyFormat), profileName, reason)
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.ransomware.\(profileName).\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when a scheduled backup was missed and automatic catch-up backup has begun.
    /// - Parameter profileName: Target backup profile name.
    public func notifyMissedBackup(profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifMissedBackupTitle)
        content.body = String(format: L10n.t(.notifMissedBackupBodyFormat), profileName)
        content.sound = .default

        dispatchNotification(identifier: "com.otterkeep.missed.\(profileName).\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when an Apple Photos library backup completes.
    /// - Parameters:
    ///   - copiedCount: Count of new photo/video assets backed up.
    ///   - durationSec: Elapsed seconds.
    public func notifyPhotosBackupCompleted(copiedCount: Int, durationSec: Double) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifPhotosCompletedTitle)
        content.body = String(format: L10n.t(.notifPhotosCompletedBodyFormat), copiedCount, durationSec)
        content.sound = .default

        dispatchNotification(identifier: "com.otterkeep.photos.completed.\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when an Apple Photos backup fails.
    /// - Parameter errorMessage: Failure description.
    public func notifyPhotosBackupFailed(errorMessage: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifPhotosFailedTitle)
        content.body = errorMessage
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.photos.failed.\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when a file restoration completes successfully.
    /// - Parameters:
    ///   - fileName: Restored file name.
    ///   - profileName: Name of the source profile.
    public func notifyRestoreCompleted(fileName: String, profileName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifRestoreCompletedTitle)
        content.body = String(format: L10n.t(.notifRestoreCompletedBodyFormat), fileName, profileName)
        content.sound = .default

        dispatchNotification(identifier: "com.otterkeep.restore.completed.\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when a file restoration fails.
    /// - Parameters:
    ///   - fileName: Target file name.
    ///   - errorMessage: Error message description.
    public func notifyRestoreFailed(fileName: String, errorMessage: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifRestoreFailedTitle)
        content.body = "\(fileName): \(errorMessage)"
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.restore.failed.\(UUID().uuidString)", content: content)
    }

    /// Delivers a critical notification when storage space on destination is critically low.
    public func notifyLowDiskSpace(availableBytes: Int64, requiredBytes: Int64, destinationName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifLowDiskSpaceTitle)
        let availStr = ByteCountFormatter.string(fromByteCount: availableBytes, countStyle: .file)
        let reqStr = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
        content.body = String(format: L10n.t(.notifLowDiskSpaceBodyFormat), destinationName, availStr, reqStr)
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.diskspace.\(UUID().uuidString)", content: content)
    }

    /// Delivers a critical alert when permission (e.g. Full Disk Access) is denied.
    public func notifyTCCPermissionDenied(folderPath: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifTCCPermissionTitle)
        content.body = String(format: L10n.t(.notifTCCPermissionBodyFormat), folderPath)
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.tcc.\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when a destination drive is disconnected during active backup.
    public func notifyDestinationDisconnected(profileName: String, driveName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifDestinationDisconnectedTitle)
        content.body = String(format: L10n.t(.notifDestinationDisconnectedBodyFormat), driveName, profileName)
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.disconnected.\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when retention pruning is completed.
    public func notifyPruningCompleted(profileName: String, prunedCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifPruningCompletedTitle)
        content.body = String(format: L10n.t(.notifPruningCompletedBodyFormat), prunedCount, profileName)
        content.sound = .default

        dispatchNotification(identifier: "com.otterkeep.prune.completed.\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when an external backup volume is mounted and backup starts automatically.
    public func notifyVolumeMountTrigger(profileName: String, volumeName: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifVolumeMountTriggerTitle)
        content.body = String(format: L10n.t(.notifVolumeMountTriggerBodyFormat), volumeName, profileName)
        content.sound = .default

        dispatchNotification(identifier: "com.otterkeep.volumemount.\(profileName).\(UUID().uuidString)", content: content)
    }

    /// Delivers a notification when a new software update is available.
    public func notifySoftwareUpdateAvailable(version: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.notifUpdateAvailableTitle)
        content.body = String(format: L10n.t(.notifUpdateAvailableBodyFormat), version)
        content.sound = .default
        dispatchNotification(identifier: "com.otterkeep.update.available.\(version)", content: content)
    }

    /// Delivers an urgent alert notification when bit-rot or file corruption is detected by the background scrubber.
    public func notifyScrubCorruptionDetected(corruptedCount: Int, snapshotId: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.t(.scrubberCorruptedAlertTitle)
        content.body = String(format: L10n.t(.scrubberCorruptedAlertMessage), Int64(corruptedCount), snapshotId)
        content.sound = .defaultCritical

        dispatchNotification(identifier: "com.otterkeep.scrub.corruption.\(UUID().uuidString)", content: content)
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Only display banner and sound if window is not active, not visible, or notification is critical
        if !presenter.isApplicationForegroundActive() || notification.request.content.sound == .defaultCritical {
            completionHandler([.banner, .sound, .badge])
        } else {
            completionHandler([])
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        presenter.activateApplication()
        completionHandler()
    }
}
